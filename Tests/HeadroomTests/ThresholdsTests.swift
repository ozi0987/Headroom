import Testing
@testable import Headroom

struct ThresholdsTests {
    @Test func 並べ替えて重複を除く() {
        #expect(Thresholds.normalized([90, 80, 90]) == [80, 90])
    }

    @Test func 範囲外は端にそろえ5きざみに丸める() {
        #expect(Thresholds.normalized([0, 150, 72]) == [5, 70, 100])
    }

    @Test func 最大5段階まで() {
        #expect(Thresholds.normalized([10, 20, 30, 40, 50, 60]) == [10, 20, 30, 40, 50])
    }

    @Test func 空なら初期値() {
        #expect(Thresholds.normalized([]) == Thresholds.defaults)
    }

    @Test func 段階を超えたら通知() {
        #expect(Thresholds.toNotify(percent: 81, thresholds: [80, 90], alreadyNotified: 0) == 80)
    }

    @Test func 段階未満なら通知しない() {
        #expect(Thresholds.toNotify(percent: 79, thresholds: [80, 90], alreadyNotified: 0) == nil)
    }

    @Test func 通知済みの段階では再通知しない() {
        #expect(Thresholds.toNotify(percent: 85, thresholds: [80, 90], alreadyNotified: 80) == nil)
    }

    @Test func 一気に超えたら一番高い段階だけ() {
        #expect(Thresholds.toNotify(percent: 95, thresholds: [80, 90], alreadyNotified: 0) == 90)
    }

    @Test func 周期の途中で段階を上げたら新しい段階で通知() {
        // 80%で通知済み → 設定を [95] に変更 → 96%で通知される
        #expect(Thresholds.toNotify(percent: 96, thresholds: [95], alreadyNotified: 80) == 95)
    }

    @Test func 周期の途中で通知済みより低い段階を足しても鳴らない() {
        // 90%で通知済み → 50% を追加しても、すでにより高い段階で通知しているので鳴らさない
        #expect(Thresholds.toNotify(percent: 92, thresholds: [50, 80, 90], alreadyNotified: 90) == nil)
    }
}
