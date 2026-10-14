import Foundation

/// 旧名「Usage Bar for Claude」（識別名 local.claudeusagebar）からの引き継ぎ。
/// 設定と履歴を新しい場所へ移す。一度だけ実行する。
enum Migration {
    private static let oldDomain = "local.claudeusagebar"
    private static let settingKeys = [
        "notificationsEnabled", "resetNotificationsEnabled", "notificationThresholds",
        "menuBarMode", "menuBarShowsRemaining", "historyRange",
    ]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromUsageBar") else { return }
        defaults.set(true, forKey: "migratedFromUsageBar")

        if let old = UserDefaults(suiteName: oldDomain) {
            for key in settingKeys where defaults.object(forKey: key) == nil {
                if let value = old.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }

        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldHistory = support.appending(path: "ClaudeUsageBar/history.json")
        let newDirectory = support.appending(path: "Headroom", directoryHint: .isDirectory)
        let newHistory = newDirectory.appending(path: "history.json")
        if fileManager.fileExists(atPath: oldHistory.path), !fileManager.fileExists(atPath: newHistory.path) {
            try? fileManager.createDirectory(at: newDirectory, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: oldHistory, to: newHistory)
        }
    }
}
