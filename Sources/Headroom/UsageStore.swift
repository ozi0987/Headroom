import AppKit
import Observation

@MainActor
@Observable
final class UsageStore {
    /// Claude Code から最後に受け取った使用量
    private(set) var snapshot: UsageSnapshot?
    /// 最後に受け取った時刻
    private(set) var lastUpdated: Date?
    private(set) var connection: StatusLineBridge.State = .notConnected
    /// 連携・解除に失敗したときのメッセージ
    private(set) var connectionError: String?
    private(set) var notificationsAllowed = true
    /// 残り時間の表示用に1分ごとに進める時計
    private(set) var now = Date()

    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            syncNotifications()
        }
    }

    /// 段階を超えた周期で、リセットされたらお知らせする
    var resetNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(resetNotificationsEnabled, forKey: "resetNotificationsEnabled")
            syncNotifications()
        }
    }

    /// 通知する使用率の段階（小さい順）
    private(set) var thresholds: [Int] {
        didSet { UserDefaults.standard.set(thresholds, forKey: "notificationThresholds") }
    }

    /// この時間より古い値には「Claude Code を使うと更新されます」と添える
    private let quietAfter: TimeInterval = 30 * 60
    /// 保存ファイルを確認する間隔。ファイルの更新日時を見るだけなので軽い
    private let interval: Duration = .seconds(5)

    let history: UsageHistory
    /// 画像の書き出し（開発用）では通知を一切使わない
    private let sendsNotifications: Bool
    private let bridge = StatusLineBridge.live
    private let notifier = UsageNotifier()
    private var lastFileDate: Date?

    /// 連携していて、しばらく Claude Code から新しい値が届いていない
    var isQuiet: Bool {
        guard connection == .connected, let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) >= quietAfter
    }

    init(sendsNotifications: Bool = true) {
        self.sendsNotifications = sendsNotifications
        // 設定や履歴を読む前に、旧バージョンのデータを引き継ぐ
        Migration.run()
        history = UsageHistory()
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        resetNotificationsEnabled = UserDefaults.standard.object(forKey: "resetNotificationsEnabled") as? Bool ?? true
        thresholds = (UserDefaults.standard.array(forKey: "notificationThresholds") as? [Int])
            .map(Thresholds.normalized) ?? Thresholds.defaults

        refreshConnection()
        if connection == .connected {
            try? bridge.installScript()
        }
        readStatusFile()

        // 許可ダイアログの返事を待たずに始める
        if sendsNotifications {
            Task { [weak self] in
                guard let self else { return }
                notificationsAllowed = await notifier.requestAuthorization()
            }
        }
        // 分が変わるタイミングに合わせて時計を進める
        Task { [weak self] in
            while !Task.isCancelled {
                let seconds = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(seconds))
                guard let self else { return }
                now = Date()
            }
        }
        // 保存ファイルが更新されたら読み込む
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .seconds(5))
                self?.readStatusFile()
            }
        }
    }

    // MARK: - 使用量

    private func readStatusFile() {
        guard let fileDate = bridge.latestModification(), fileDate != lastFileDate else { return }
        lastFileDate = fileDate
        guard let status = bridge.readStatus() else { return }

        let snapshot = status.snapshot
        self.snapshot = snapshot
        lastUpdated = status.updatedAt
        now = Date()
        // 画像の書き出し（開発用）では、通知も履歴の書き込みもしない
        if sendsNotifications {
            notifier.check(snapshot, thresholds: thresholds, notify: notificationsEnabled, notifyReset: resetNotificationsEnabled)
            history.record(snapshot, at: status.updatedAt)
        }
    }

    // MARK: - Claude Code との連携

    func refreshConnection() {
        connection = bridge.state
    }

    func connect() {
        do {
            try bridge.connect()
            connectionError = nil
        } catch {
            connectionError = error.localizedDescription
        }
        refreshConnection()
    }

    func disconnect() {
        do {
            try bridge.disconnect()
            connectionError = nil
        } catch {
            connectionError = error.localizedDescription
        }
        refreshConnection()
    }

    // MARK: - 通知

    /// システム設定で許可を変えた場合にも追従できるよう、メニューを開くたびに呼ぶ
    func refreshNotificationPermission() async {
        guard sendsNotifications else { return }
        notificationsAllowed = await notifier.isAuthorized()
    }

    func sendTestNotification() async {
        notificationsAllowed = await notifier.requestAuthorization()
        if notificationsAllowed {
            notifier.sendTest(thresholds: thresholds)
        } else {
            openNotificationSettings()
        }
    }

    func setThresholds(_ values: [Int]) {
        thresholds = Thresholds.normalized(values)
    }

    /// 設定を変えたときに、リセットのお知らせの予約をすぐ反映する。
    /// 通知済みの段階は記録されているので、同じ通知が二重に鳴ることはない
    private func syncNotifications() {
        guard sendsNotifications, let snapshot else { return }
        notifier.check(snapshot, thresholds: thresholds, notify: notificationsEnabled, notifyReset: resetNotificationsEnabled)
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
