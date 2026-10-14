import Foundation

enum MenuBarMode: String, CaseIterable, Identifiable {
    case both = "セッションと今週"
    case session = "セッションのみ"
    case weekly = "今週のみ"
    case iconOnly = "アイコンのみ"

    var id: Self { self }
}

/// メニューバーに出す文字とアイコンを決める。UIに依存しないのでテストしやすい。
enum MenuBarFormat {
    static func text(
        mode: MenuBarMode,
        showsRemaining: Bool,
        snapshot: UsageSnapshot?,
        hasError: Bool,
        now: Date
    ) -> String {
        if hasError && snapshot == nil { return "!" }
        guard let snapshot = snapshot?.current(at: now) else { return mode == .iconOnly ? "" : "…" }

        var parts: [String]
        switch mode {
        case .both: parts = [percent(snapshot.session), percent(snapshot.weekly)]
        case .session: parts = [percent(snapshot.session)]
        case .weekly: parts = [percent(snapshot.weekly)]
        case .iconOnly: parts = []
        }
        if showsRemaining, let reset = snapshot.session?.resetsAt {
            parts.append("残" + compactRemaining(until: reset, now: now))
        }
        return parts.joined(separator: " · ")
    }

    /// 表示している値のうち高いほうに合わせて、メーターの針を動かす
    static func gaugeSymbol(mode: MenuBarMode, snapshot: UsageSnapshot?, now: Date) -> String {
        let snapshot = snapshot?.current(at: now)
        let values: [Double?] = switch mode {
        case .both, .iconOnly: [snapshot?.session?.percent, snapshot?.weekly?.percent]
        case .session: [snapshot?.session?.percent]
        case .weekly: [snapshot?.weekly?.percent]
        }
        let level = values.compactMap { $0 }.max() ?? 0
        let needle = switch level {
        case ..<17: "0"
        case ..<42: "33"
        case ..<58: "50"
        case ..<84: "67"
        default: "100"
        }
        return "gauge.with.dots.needle.\(needle)percent"
    }

    /// メニューバー用の短い残り時間（1:19 / 0:05）
    static func compactRemaining(until date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private static func percent(_ window: UsageWindow?) -> String {
        window.map { "\(Int($0.percent.rounded()))%" } ?? "–"
    }
}
