import SwiftUI

struct MenuBarLabel: View {
    let store: UsageStore

    @AppStorage("menuBarMode") private var mode: MenuBarMode = .both
    @AppStorage("menuBarShowsRemaining") private var showsRemaining = false

    var body: some View {
        let text = MenuBarFormat.text(
            mode: mode,
            showsRemaining: showsRemaining,
            snapshot: store.snapshot,
            hasError: store.connection == .notConnected,
            now: store.now
        )
        HStack(spacing: 4) {
            Image(systemName: MenuBarFormat.gaugeSymbol(mode: mode, snapshot: store.snapshot, now: store.now))
            if !text.isEmpty {
                Text(text)
            }
        }
    }
}

struct UsageView: View {
    @Bindable var store: UsageStore
    @State private var showingSettings: Bool
    @State private var contentHeight: CGFloat = 0

    init(store: UsageStore, showingSettings: Bool = false) {
        _store = Bindable(store)
        _showingSettings = State(initialValue: showingSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.connection == .notConnected {
                ConnectBanner(store: store)
            } else if store.snapshot == nil {
                StatusNote(text: "連携しました。Claude Code で何か送ると、ここに使用量が表示されます（Claude Code の再起動が必要な場合があります）。")
            } else if store.isQuiet {
                StatusNote(text: "Claude Code を使うと更新されます。")
            }

            UsageRow(
                title: "現在のセッション",
                subtitle: sessionSubtitle,
                detail: sessionRemaining,
                window: store.snapshot?.session,
                now: store.now
            )
            UsageRow(
                title: "今週",
                subtitle: weeklySubtitle,
                window: store.snapshot?.weekly,
                now: store.now
            )

            Divider()

            HistoryChartView(samples: store.history.samples, thresholds: store.thresholds)

            Divider()

            if showingSettings {
                SettingsView(store: store)
            }

            HStack(spacing: 12) {
                Text(lastUpdatedText)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingSettings.toggle()
                } label: {
                    Label(showingSettings ? "完了" : "設定", systemImage: showingSettings ? "checkmark" : "gearshape")
                }
                .help("Claude Code との連携・メニューバーの表示・通知・起動の設定")

                Button("終了") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(WindowHeightFitter(contentHeight: contentHeight))
        .task {
            store.refreshConnection()
            await store.refreshNotificationPermission()
        }
    }

    private var sessionSubtitle: String {
        guard let window = store.snapshot?.session else { return "" }
        if window.hasReset(at: store.now) { return "リセットされました" }
        return window.resetsAt.map { "\(timeFormatter.string(from: roundedToMinute($0)))にリセットされます" } ?? ""
    }

    /// 「あと1時間12分」は途中で折り返さないよう2行目に分ける
    private var sessionRemaining: String? {
        guard let window = store.snapshot?.session, !window.hasReset(at: store.now) else { return nil }
        return window.resetsAt.map { remainingText(until: $0, now: store.now) }
    }

    private var weeklySubtitle: String {
        guard let window = store.snapshot?.weekly else { return "" }
        if window.hasReset(at: store.now) { return "リセットされました" }
        return window.resetsAt.map(weeklyResetText) ?? ""
    }

    private var lastUpdatedText: String {
        guard let date = store.lastUpdated else { return "未取得" }
        let time = "最終更新 \(timeFormatter.string(from: date))"
        // しばらく届いていないときは、どれくらい前の値なのかを添える
        return store.isQuiet ? "\(time)（\(agoText(from: date, now: store.now))）" : time
    }
}

/// まだ連携していないときの案内。押す前に何をするのかを必ず見せる
struct ConnectBanner: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude Code と連携すると、使用量が表示されます", systemImage: "link")
                .font(.callout.bold())
            ConnectExplanation()
            if let error = store.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Claude Code と連携する") { store.connect() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 連携で何が起きるかの説明（案内と設定欄で共通）
struct ConnectExplanation: View {
    var body: some View {
        Text("Claude Code の設定（~/.claude/settings.json）に、ステータスラインを追加します。Claude Code が表示用に渡してくる使用量だけを保存し、ログイン情報や会話の内容には触れません。元の設定はバックアップし、解除すると元に戻ります。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 連携済みのときの補足
struct StatusNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// メニューのウィンドウは、中身が小さくなっても自動では縮まない（設定欄を閉じると下に空白が残る）。
/// 中身の高さが変わるたびに、上端の位置を保ったままウィンドウの高さを合わせる。
private struct WindowHeightFitter: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard contentHeight > 0 else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 0, height: contentHeight)).height
            var frame = window.frame
            guard abs(frame.height - target) > 1 else { return }
            frame.origin.y += frame.height - target  // 上端（メニューバー側）を動かさない
            frame.size.height = target
            window.setFrame(frame, display: true)
        }
    }
}

struct UsageRow: View {
    let title: String
    let subtitle: String
    var detail: String? = nil
    let window: UsageWindow?
    let now: Date

    /// リセット時刻を過ぎた古い値は表示しない
    private var current: UsageWindow? {
        window.flatMap { $0.hasReset(at: now) ? nil : $0 }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                UsageBar(fraction: (current?.percent ?? 0) / 100)
                Text(current.map { "\(Int($0.percent.rounded()))% 使用済み" } ?? "–")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }

    /// 70%で橙、90%で赤にして「そろそろ危ない」を一目でわかるようにする
    private var color: Color {
        switch fraction {
        case ..<0.7: .blue
        case ..<0.9: .orange
        default: .red
        }
    }
}
