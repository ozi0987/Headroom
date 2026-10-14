import Foundation
import UserNotifications

/// 使用率がしきい値を超えたら通知する。
/// 同じリセット周期の中では、同じしきい値で2回通知しない（アプリを再起動しても）。
@MainActor
final class UsageNotifier {
    private let defaults = UserDefaults.standard
    private let delegate = BannerDelegate()
    /// 実際に通知を使うときまで触らない（通知の仕組みはアプリとして起動したときしか使えないため）
    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        return center
    }()

    /// 許可されていれば true。未確認なら許可ダイアログを出す（拒否済みなら何も出さず false）
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// ダイアログを出さずに、いま許可されているかだけ確認する
    func isAuthorized() async -> Bool {
        await center.notificationSettings().authorizationStatus == .authorized
    }

    func check(_ snapshot: UsageSnapshot, thresholds: [Int], notify: Bool, notifyReset: Bool) {
        let session = Target(key: "session", title: "現在のセッション", resetTitle: "セッションがリセットされました") {
            sessionResetText($0)
        }
        let weekly = Target(key: "weekly", title: "今週", resetTitle: "週の使用量がリセットされました") {
            weeklyResetText($0)
        }
        for (target, window) in [(session, snapshot.session), (weekly, snapshot.weekly)] {
            guard let window else { continue }
            evaluate(target, window: window, thresholds: thresholds, notify: notify)
            syncResetReminder(target, window: window, enabled: notify && notifyReset)
        }
    }

    private struct Target {
        let key: String
        let title: String
        let resetTitle: String
        let resetText: (Date) -> String

        var cycleKey: String { "notify.\(key).cycle" }
        var levelKey: String { "notify.\(key).level" }
        var reminderID: String { "reset.\(key)" }
    }

    func sendTest(thresholds: [Int]) {
        post(title: "Headroom", body: "通知のテストです。使用率が\(Thresholds.label(thresholds))を超えるとお知らせします。")
    }

    private func evaluate(_ target: Target, window: UsageWindow, thresholds: [Int], notify: Bool) {
        // resets_at が変わったら新しい周期なので、通知済みレベルをリセットする
        let cycle = window.resetsAt.map { Int(roundedToMinute($0).timeIntervalSince1970) } ?? 0
        let cycleKey = target.cycleKey
        let levelKey = target.levelKey
        if defaults.integer(forKey: cycleKey) != cycle {
            defaults.set(cycle, forKey: cycleKey)
            defaults.set(0, forKey: levelKey)
        }

        let percent = Int(window.percent.rounded())
        guard let crossed = Thresholds.toNotify(
            percent: percent,
            thresholds: thresholds,
            alreadyNotified: defaults.integer(forKey: levelKey)
        ) else { return }

        // 通知オフの間も記録だけは進め、オンにした瞬間にまとめて鳴らないようにする
        defaults.set(crossed, forKey: levelKey)
        guard notify else { return }

        var body = "使用率が\(percent)%になりました。"
        if let reset = window.resetsAt {
            body += target.resetText(reset)
        }
        post(title: "\(target.title)：\(crossed)%を超えました", body: body)
    }

    /// 段階を超えた周期なら、リセット時刻ちょうどに鳴るお知らせを macOS に予約しておく。
    /// 予約なので、アプリが終了していても・ログイン情報が期限切れでも時間どおりに届く。
    private func syncResetReminder(_ target: Target, window: UsageWindow, enabled: Bool) {
        let level = defaults.integer(forKey: target.levelKey)
        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [target.reminderID])
            return
        }
        guard let delay = Thresholds.resetReminderDelay(notifiedLevel: level, resetsAt: window.resetsAt, now: Date()) else {
            // 新しい周期でまだ段階を超えていない → 前の周期の予約が残っていれば消す
            if level == 0 {
                center.removePendingNotificationRequests(withIdentifiers: [target.reminderID])
            }
            return
        }
        // 同じ ID で追加すると上書きされるので、2分ごとに呼ばれても予約は1つだけ
        post(
            title: target.resetTitle,
            body: "また Claude を使えるようになりました。",
            id: target.reminderID,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
    }

    private func post(
        title: String,
        body: String,
        id: String = UUID().uuidString,
        trigger: UNNotificationTrigger? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// メニューを開いている（＝アプリが前面の）ときもバナーを出す
private final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
