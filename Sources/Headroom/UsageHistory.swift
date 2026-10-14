import Foundation
import Observation

struct UsageSample: Codable, Sendable {
    let date: Date
    let session: Double?
    let weekly: Double?
}

/// 使用率の履歴を ~/Library/Application Support/Headroom/history.json に保存する
@MainActor
@Observable
final class UsageHistory {
    private(set) var samples: [UsageSample] = []

    /// 保存しておく期間
    private let retention: TimeInterval = 14 * 24 * 3600
    /// 値が変わらなくても、この間隔ごとには記録する
    private let keepAliveInterval: TimeInterval = 10 * 60
    private let fileURL: URL?

    init(samples: [UsageSample]? = nil) {
        guard samples == nil else {
            // プレビュー・スナップショット用（保存しない）
            self.samples = samples ?? []
            fileURL = nil
            return
        }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Headroom", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "history.json")
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([UsageSample].self, from: data) {
            self.samples = decoded
        }
    }

    /// Claude Code は返答のたびに値を渡してくるので、すべて保存すると多すぎる。
    /// 値が変わったとき・前回から10分たったときだけ記録する
    func record(_ snapshot: UsageSnapshot, at date: Date = Date()) {
        let sample = UsageSample(date: date, session: snapshot.session?.percent, weekly: snapshot.weekly?.percent)
        // アプリを再起動して同じファイルを読み直したときなど、記録済みの時刻より前なら無視する
        if let last = samples.last, date <= last.date { return }
        if let last = samples.last,
           last.session == sample.session,
           last.weekly == sample.weekly,
           date.timeIntervalSince(last.date) < keepAliveInterval {
            return
        }
        samples.append(sample)
        samples.removeAll { date.timeIntervalSince($0.date) > retention }
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
