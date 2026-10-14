#if DEBUG
import AppKit
import SwiftUI

/// 開発用：記事に使うアプリの画面を、実際のデータで画像に書き出す。
/// 画面を撮影するのではなく、画面外のウィンドウに描いて書き出すので、
/// 画面収録の許可は不要で、ほかのアプリや通知も写り込まない。
@MainActor
enum ScreenCapture {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = UsageStore(sendsNotifications: false)
        let defaults = UserDefaults.standard
        // 記事では、記録が多く見栄えのする7日表示にする
        defaults.set(HistoryRange.week.rawValue, forKey: "historyRange")

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            defaults.set(MenuBarMode.both.rawValue, forKey: "menuBarMode")
            defaults.set(false, forKey: "menuBarShowsRemaining")

            capture(MenuBarScene(store: store, showingSettings: false), scheme: scheme,
                    to: dir.appending(path: "メニュー-\(suffix).png"))
            capture(MenuBarScene(store: store, showingSettings: true), scheme: scheme,
                    to: dir.appending(path: "設定欄-\(suffix).png"))
            capture(Card { ConnectBanner(store: store) }, scheme: scheme,
                    to: dir.appending(path: "連携の案内-\(suffix).png"))

            // メニューバーの表示パターン（第5回）
            var strips: [(String, MenuBarMode, Bool)] = MenuBarMode.allCases.map { ($0.rawValue, $0, false) }
            strips.append(("セッションと今週＋残り時間", .both, true))
            capture(MenuBarPatterns(store: store, patterns: strips), scheme: scheme,
                    to: dir.appending(path: "メニューバーの表示パターン-\(suffix).png"))
        }

        // メーターの針が使用率で動く様子（第5回）
        capture(NeedleSteps(), scheme: .light, to: dir.appending(path: "メーターの針.png"))

        // 記録が1時間分しかないときの拡大表示（第9回の修正後）。実際の状況と同じ値で再現する
        let now = Date()
        let short = (0...6).map { i in
            UsageSample(date: now.addingTimeInterval(Double(i - 6) * 600), session: 22 + Double(i) * 3.5, weekly: 38 + Double(i) / 3)
        }
        capture(Card { HistoryChartView(samples: short, now: now, showsRangePicker: false) }, scheme: .light,
                to: dir.appending(path: "修正後のグラフ.png"))
        print("wrote screens to \(dir.path)")
    }

    private static func capture(_ view: some View, scheme: ColorScheme, to url: URL) {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        NSApplication.shared.appearance = appearance
        let hosting = NSHostingView(rootView: AnyView(view.environment(\.colorScheme, scheme)))
        hosting.appearance = appearance
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        // グラフや非同期の読み込みが描き終わるのを少し待つ
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// メニューバーと、開いたメニュー。デスクトップ風の背景に置く
private struct MenuBarScene: View {
    let store: UsageStore
    let showingSettings: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            MenuBarStrip { MenuBarLabel(store: store) }
            UsageView(store: store, showingSettings: showingSettings)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .padding(.trailing, 70)
                .padding(.bottom, 40)
        }
        .frame(width: 640)
        .background(Desktop())
    }
}

/// メーターのアイコンが使用率に合わせて5段階で変わる様子
private struct NeedleSteps: View {
    var body: some View {
        HStack(spacing: 28) {
            ForEach([(0.0, "〜16%"), (30, "17〜41%"), (50, "42〜57%"), (70, "58〜83%"), (95, "84%〜")], id: \.1) { value, label in
                VStack(spacing: 10) {
                    Image(systemName: MenuBarFormat.gaugeSymbol(
                        mode: .session,
                        snapshot: UsageSnapshot(session: UsageWindow(percent: value, resetsAt: nil), weekly: nil),
                        now: Date()
                    ))
                    .font(.system(size: 44))
                    Text(label).font(.system(size: 13, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .padding(28)
        .background(Desktop())
    }
}

/// メニューバーの表示パターンを縦に並べる
private struct MenuBarPatterns: View {
    let store: UsageStore
    let patterns: [(String, MenuBarMode, Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(patterns, id: \.0) { name, mode, remaining in
                HStack(spacing: 16) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 190, alignment: .leading)
                    MenuBarStrip { PatternLabel(store: store, mode: mode, showsRemaining: remaining) }
                        .frame(width: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(24)
        .background(Desktop())
    }
}

/// MenuBarLabel と同じ中身を、表示パターンを指定して描く
private struct PatternLabel: View {
    let store: UsageStore
    let mode: MenuBarMode
    let showsRemaining: Bool

    var body: some View {
        let text = MenuBarFormat.text(mode: mode, showsRemaining: showsRemaining, snapshot: store.snapshot,
                                      hasError: false, now: store.now)
        HStack(spacing: 4) {
            Image(systemName: MenuBarFormat.gaugeSymbol(mode: mode, snapshot: store.snapshot, now: store.now))
            if !text.isEmpty { Text(text) }
        }
    }
}

/// メニューバー風の帯（右端に時計）
private struct MenuBarStrip<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            content
            Text("9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
    }
}

/// 単体の部品をカード状に置く
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(width: 380)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            .padding(32)
            .background(Desktop())
    }
}

/// デスクトップ風の背景（見出し画像と同じ系統の明るい色）
private struct Desktop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.16, green: 0.20, blue: 0.32), Color(red: 0.10, green: 0.11, blue: 0.16)]
                : [Color(red: 0.87, green: 0.93, blue: 1.0), Color(red: 1.0, green: 0.92, blue: 0.84)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
#endif
