import Foundation
import Testing
@testable import Headroom

struct ChartTimeAxisTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
    /// 2026-10-05 02:35 JST（スクショの状況）
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 2, minute: 35))! }

    @Test func 記録が十分あれば24時間をそのまま表示() {
        let axis = ChartTimeAxis.make(range: .day, firstSample: now.addingTimeInterval(-3 * 86400), now: now, calendar: calendar)
        #expect(!axis.isZoomed)
        #expect(axis.domain.lowerBound == now.addingTimeInterval(-86400))
        #expect(!axis.usesDayLabels)
    }

    @Test func 記録が1時間しかなければ拡大する() {
        let axis = ChartTimeAxis.make(range: .day, firstSample: now.addingTimeInterval(-3600), now: now, calendar: calendar)
        #expect(axis.isZoomed)
        // 最低3時間の幅は見せる
        #expect(axis.domain.lowerBound == now.addingTimeInterval(-ChartTimeAxis.minimumSpan))
        #expect(axis.ticks.count >= 2)
    }

    @Test func 端に近い目盛りは出さない() {
        // 02:35 の24時間表示では、02:00 の目盛りは右端に近すぎる（スクショの「…」）
        let axis = ChartTimeAxis.make(range: .day, firstSample: nil, now: now, calendar: calendar)
        let twoAM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 2))!
        #expect(!axis.ticks.contains(twoAM))
        #expect(axis.ticks.count >= 3)
    }

    @Test func 七日表示は曜日の目盛り() {
        let axis = ChartTimeAxis.make(range: .week, firstSample: now.addingTimeInterval(-10 * 86400), now: now, calendar: calendar)
        #expect(axis.usesDayLabels)
        #expect((5...7).contains(axis.ticks.count))
    }
}
