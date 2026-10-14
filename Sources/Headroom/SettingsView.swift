import ServiceManagement
import SwiftUI

/// 「⚙ 設定」で開く設定欄（メニューバー・通知・その他）
struct SettingsView: View {
    @Bindable var store: UsageStore

    @AppStorage("menuBarMode") private var menuBarMode: MenuBarMode = .both
    @AppStorage("menuBarShowsRemaining") private var showsRemaining = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var draft: [DraftThreshold] = []

    /// 編集中は並べ替えや重複の整理をせず、設定欄を閉じたときにまとめて反映する
    /// （ステッパー操作中に行が入れ替わったり消えたりしないように）
    private struct DraftThreshold: Identifiable {
        let id = UUID()
        var value: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Claude Code との連携") {
                if store.connection == .connected {
                    HStack {
                        Label("連携中", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("連携を解除") { store.disconnect() }
                    }
                    Text("解除すると、Claude Code のステータスラインを連携前の状態に戻します。")
                        .foregroundStyle(.secondary)
                } else {
                    ConnectExplanation()
                    Button("Claude Code と連携する") { store.connect() }
                }
                if let error = store.connectionError {
                    Text(error).foregroundStyle(.orange)
                }
            }

            section("メニューバー") {
                Picker("表示", selection: $menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Toggle("セッションのリセットまでの残り時間を表示", isOn: $showsRemaining)
                    .toggleStyle(.checkbox)
            }

            section("通知") {
                Toggle("使用率が次の段階を超えたら通知", isOn: $store.notificationsEnabled)
                    .toggleStyle(.checkbox)
                thresholdEditor
                    .disabled(!store.notificationsEnabled)
                Toggle("段階を超えたあと、リセットされたら通知", isOn: $store.resetNotificationsEnabled)
                    .toggleStyle(.checkbox)
                    .disabled(!store.notificationsEnabled)
                if !store.notificationsAllowed {
                    Button("通知が許可されていません。システム設定を開く") {
                        store.openNotificationSettings()
                    }
                    .buttonStyle(.link)
                }
            }

            section("その他") {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                Text("バージョン \(appVersion)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            draft = store.thresholds.map { DraftThreshold(value: $0) }
        }
        // 設定欄を閉じたとき・メニューを閉じたときに段階を反映する
        .onDisappear {
            store.setThresholds(draft.map(\.value))
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? ProcessInfo.processInfo.environment["HEADROOM_VERSION"]  // 開発用の画像書き出しで使う
            ?? "開発版"
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var thresholdEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($draft) { $item in
                HStack {
                    Stepper(value: $item.value, in: Thresholds.range, step: Thresholds.step) {
                        Text("\(item.value)%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Spacer()
                    Button {
                        draft.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(draft.count <= 1)
                    .help("この段階を削除")
                }
            }

            HStack {
                Button {
                    draft.append(DraftThreshold(value: nextValue()))
                } label: {
                    Label("段階を追加", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(draft.count >= Thresholds.maxCount)

                Spacer()

                Button("初期値に戻す") {
                    draft = Thresholds.defaults.map { DraftThreshold(value: $0) }
                }
                .buttonStyle(.borderless)

                Button("テスト通知") {
                    Task { await store.sendTestNotification() }
                }
            }

            Text("\(Thresholds.step)%きざみ・最大\(Thresholds.maxCount)段階。同じ値は1つにまとめます")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
    }

    /// 追加する段階の初期値：今ある最大値の5%上（100%を超えるなら最小値の5%下）
    private func nextValue() -> Int {
        let values = draft.map(\.value)
        let above = (values.max() ?? 70) + Thresholds.step
        if above <= Thresholds.range.upperBound { return above }
        return max((values.min() ?? 80) - Thresholds.step, Thresholds.range.lowerBound)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
