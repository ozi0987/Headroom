import Foundation

/// 使用量の1つの枠（5時間セッション / 週）
struct UsageWindow: Codable, Sendable {
    let percent: Double
    let resetsAt: Date?

    /// リセット時刻を過ぎていたら、この値はもう古い（リセット後の値はわからない）
    func hasReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }
}

struct UsageSnapshot: Codable, Sendable {
    let session: UsageWindow?
    let weekly: UsageWindow?

    /// リセット時刻を過ぎた枠を取り除いたもの（表示用）
    func current(at now: Date) -> UsageSnapshot {
        UsageSnapshot(
            session: session.flatMap { $0.hasReset(at: now) ? nil : $0 },
            weekly: weekly.flatMap { $0.hasReset(at: now) ? nil : $0 }
        )
    }
}

/// ステータスラインのスクリプトが保存したファイル（sessions/<セッションID>.json）の中身
struct StatusFile: Decodable {
    struct Limits: Decodable {
        struct Window: Decodable {
            let used_percentage: Double?
            let resets_at: Double?

            var window: UsageWindow? {
                guard let used_percentage else { return nil }
                return UsageWindow(percent: used_percentage, resetsAt: resets_at.map(Date.init(timeIntervalSince1970:)))
            }
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    /// スクリプトが保存した時刻（Unix 秒）
    let updated_at: Double
    let rate_limits: Limits

    var updatedAt: Date { Date(timeIntervalSince1970: updated_at) }

    var snapshot: UsageSnapshot {
        UsageSnapshot(session: rate_limits.five_hour?.window, weekly: rate_limits.seven_day?.window)
    }
}

/// 複数の Claude Code セッションの値をまとめたもの
struct MergedStatus {
    let snapshot: UsageSnapshot
    /// いずれかのセッションから最後に値が届いた時刻
    let updatedAt: Date

    /// しばらく使っていないセッションは、古い使用量を持ったまま画面を更新することがある。
    /// 同じ周期の中で使用率は下がらないので、
    /// 「リセット時刻がより新しい値」→「同じ周期なら使用率が高い値」を正しい値として選ぶ。
    static func merge(_ statuses: [StatusFile]) -> MergedStatus? {
        guard let updatedAt = statuses.map(\.updatedAt).max() else { return nil }
        let snapshots = statuses.map(\.snapshot)
        return MergedStatus(
            snapshot: UsageSnapshot(
                session: latest(snapshots.map(\.session)),
                weekly: latest(snapshots.map(\.weekly))
            ),
            updatedAt: updatedAt
        )
    }

    static func latest(_ windows: [UsageWindow?]) -> UsageWindow? {
        windows.compactMap { $0 }.max { a, b in
            // resets_at の秒のぶれで別の周期と見なさないよう、分単位でそろえて比べる
            let resetA = a.resetsAt.map(roundedToMinute) ?? .distantPast
            let resetB = b.resetsAt.map(roundedToMinute) ?? .distantPast
            return resetA == resetB ? a.percent < b.percent : resetA < resetB
        }
    }
}
