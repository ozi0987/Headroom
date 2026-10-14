import Foundation

/// 通知の段階（しきい値）に関するルール。UIや通知APIに依存しないのでテストしやすい。
enum Thresholds {
    static let defaults = [80, 90]
    static let range = 5...100
    static let step = 5
    static let maxCount = 5

    /// 範囲内に収め、5%きざみにそろえ、重複を除いて小さい順に並べる
    static func normalized(_ values: [Int]) -> [Int] {
        let snapped = values.map { value in
            let rounded = Int((Double(value) / Double(step)).rounded()) * step
            return min(max(rounded, range.lowerBound), range.upperBound)
        }
        let result = Array(Array(Set(snapped)).sorted().prefix(maxCount))
        return result.isEmpty ? defaults : result
    }

    /// 今回通知すべき段階。なければ nil。
    /// 一気に複数の段階を超えたときは、いちばん高いものだけを返す。
    /// - Parameter alreadyNotified: この周期ですでに通知した最も高い段階（未通知なら 0）
    static func toNotify(percent: Int, thresholds: [Int], alreadyNotified: Int) -> Int? {
        guard let crossed = thresholds.sorted().last(where: { percent >= $0 }),
              crossed > alreadyNotified
        else { return nil }
        return crossed
    }

    /// リセットのお知らせを予約するまでの秒数。予約しないなら nil。
    /// 毎回のリセットで鳴るとうるさいので、この周期で段階を超えていたときだけ知らせる。
    static func resetReminderDelay(notifiedLevel: Int, resetsAt: Date?, now: Date) -> TimeInterval? {
        guard notifiedLevel > 0, let resetsAt else { return nil }
        let delay = resetsAt.timeIntervalSince(now)
        return delay > 0 ? delay : nil
    }

    /// 「80%・90%」のような表示用の文字列
    static func label(_ values: [Int]) -> String {
        values.map { "\($0)%" }.joined(separator: "・")
    }
}
