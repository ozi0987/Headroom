import Foundation
import Testing
@testable import Headroom

struct ResetReminderTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func 段階を超えた周期ならリセット時刻に予約() {
        #expect(Thresholds.resetReminderDelay(notifiedLevel: 80, resetsAt: now.addingTimeInterval(600), now: now) == 600)
    }

    @Test func 段階を超えていなければ予約しない() {
        #expect(Thresholds.resetReminderDelay(notifiedLevel: 0, resetsAt: now.addingTimeInterval(600), now: now) == nil)
    }

    @Test func リセット時刻を過ぎていたら予約しない() {
        #expect(Thresholds.resetReminderDelay(notifiedLevel: 90, resetsAt: now.addingTimeInterval(-1), now: now) == nil)
    }

    @Test func リセット時刻が不明なら予約しない() {
        #expect(Thresholds.resetReminderDelay(notifiedLevel: 90, resetsAt: nil, now: now) == nil)
    }
}
