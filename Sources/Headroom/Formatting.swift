import Foundation

let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "H:mm"
    return formatter
}()

let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "EEEE"
    return formatter
}()

/// 公式画面と同じく、18:49:59 →「18:50」のように分単位で丸める
func roundedToMinute(_ date: Date) -> Date {
    Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
}

func remainingText(until date: Date, now: Date = Date()) -> String {
    let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
    let hours = minutes / 60
    return hours > 0 ? "あと\(hours)時間\(minutes % 60)分" : "あと\(minutes)分"
}

/// 「23分前」「2時間前」「3日前」
func agoText(from date: Date, now: Date = Date()) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    if minutes < 1 { return "たった今" }
    if minutes < 60 { return "\(minutes)分前" }
    if minutes < 24 * 60 { return "\(minutes / 60)時間前" }
    return "\(minutes / (24 * 60))日前"
}

func sessionResetText(_ reset: Date, now: Date = Date()) -> String {
    "\(timeFormatter.string(from: roundedToMinute(reset)))にリセットされます（\(remainingText(until: reset, now: now))）"
}

func weeklyResetText(_ reset: Date) -> String {
    let date = roundedToMinute(reset)
    return "\(timeFormatter.string(from: date)) (\(weekdayFormatter.string(from: date)))にリセット"
}
