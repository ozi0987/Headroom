import Foundation
import Testing
@testable import Headroom

struct MenuBarFormatTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    var snapshot: UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(percent: 22, resetsAt: now.addingTimeInterval(79 * 60 + 30)),
            weekly: UsageWindow(percent: 38, resetsAt: now.addingTimeInterval(3 * 24 * 3600))
        )
    }

    func text(_ mode: MenuBarMode, remaining: Bool = false, snapshot: UsageSnapshot?, error: Bool = false) -> String {
        MenuBarFormat.text(mode: mode, showsRemaining: remaining, snapshot: snapshot, hasError: error, now: now)
    }

    @Test func 両方() { #expect(text(.both, snapshot: snapshot) == "22% · 38%") }
    @Test func セッションのみ() { #expect(text(.session, snapshot: snapshot) == "22%") }
    @Test func 今週のみ() { #expect(text(.weekly, snapshot: snapshot) == "38%") }
    @Test func アイコンのみは文字なし() { #expect(text(.iconOnly, snapshot: snapshot) == "") }

    @Test func 残り時間つき() {
        #expect(text(.both, remaining: true, snapshot: snapshot) == "22% · 38% · 残1:19")
        #expect(text(.iconOnly, remaining: true, snapshot: snapshot) == "残1:19")
    }

    @Test func 取得前とエラー() {
        #expect(text(.both, snapshot: nil) == "…")
        #expect(text(.iconOnly, snapshot: nil) == "")
        #expect(text(.iconOnly, snapshot: nil, error: true) == "!")
        // 一度取れていれば、一時的なエラーでも前回の値を出し続ける
        #expect(text(.both, snapshot: snapshot, error: true) == "22% · 38%")
    }

    @Test func 残り時間は0未満にならない() {
        #expect(MenuBarFormat.compactRemaining(until: now.addingTimeInterval(-60), now: now) == "0:00")
        #expect(MenuBarFormat.compactRemaining(until: now.addingTimeInterval(5 * 60), now: now) == "0:05")
    }

    func gauge(_ mode: MenuBarMode, _ snapshot: UsageSnapshot?, at time: Date? = nil) -> String {
        MenuBarFormat.gaugeSymbol(mode: mode, snapshot: snapshot, now: time ?? now)
    }

    @Test func メーターは表示中の高いほうに合わせる() {
        #expect(gauge(.both, snapshot) == "gauge.with.dots.needle.33percent")
        #expect(gauge(.session, snapshot) == "gauge.with.dots.needle.33percent")
        let high = UsageSnapshot(session: UsageWindow(percent: 92, resetsAt: nil), weekly: UsageWindow(percent: 10, resetsAt: nil))
        #expect(gauge(.both, high) == "gauge.with.dots.needle.100percent")
        #expect(gauge(.weekly, high) == "gauge.with.dots.needle.0percent")
    }

    @Test func リセット時刻を過ぎた枠は古い値を出さない() {
        // セッションのリセット（79分後）を過ぎた時点
        let later = now.addingTimeInterval(2 * 3600)
        #expect(MenuBarFormat.text(mode: .both, showsRemaining: true, snapshot: snapshot, hasError: true, now: later) == "– · 38%")
        #expect(gauge(.session, snapshot, at: later) == "gauge.with.dots.needle.0percent")
    }

    @Test func 何分前の表示() {
        #expect(agoText(from: now, now: now) == "たった今")
        #expect(agoText(from: now.addingTimeInterval(-23 * 60), now: now) == "23分前")
        #expect(agoText(from: now.addingTimeInterval(-3 * 3600), now: now) == "3時間前")
        #expect(agoText(from: now.addingTimeInterval(-50 * 3600), now: now) == "2日前")
    }

    @Test func 保存して読み戻せる() throws {
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        #expect(decoded.session?.percent == 22)
        #expect(decoded.weekly?.resetsAt == snapshot.weekly?.resetsAt)
    }
}
