#if DEBUG
import AppKit
import SwiftUI

/// 開発用：`Headroom --snapshot <出力先フォルダ>` でグラフをPNGに書き出して終了する
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[index + 1])
        let now = Date()

        // --screens：実際のデータで、記事用のアプリ画面を書き出す
        if args.contains("--screens") {
            ScreenCapture.run(to: dir)
            exit(0)
        }

        // --real：実際の履歴でグラフを書き出す（記事用）
        if args.contains("--real") {
            UserDefaults.standard.set(HistoryRange.day.rawValue, forKey: "historyRange")
            let samples = UsageHistory().samples
            for scheme in [ColorScheme.light, .dark] {
                render(
                    HistoryChartView(samples: samples, now: now, showsRangePicker: false),
                    name: "chart-real-\(scheme == .dark ? "dark" : "light")", scheme: scheme, to: dir
                )
            }
            exit(0)
        }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            for range in HistoryRange.allCases {
                UserDefaults.standard.set(range.rawValue, forKey: "historyRange")
                let view = HistoryChartView(samples: sampleData(now: now), now: now)
                    .padding(16)
                    .frame(width: 380)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                NSApplication.shared.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appending(path: "chart-\(range == .day ? "day" : "week")-\(name).png"))
                }
            }
        }
        // 記録を始めて1時間しかたっていない状態（拡大表示の確認用）
        UserDefaults.standard.set(HistoryRange.day.rawValue, forKey: "historyRange")
        let short = (0...6).map { i in
            UsageSample(date: now.addingTimeInterval(Double(i - 6) * 600), session: 22 + Double(i) * 3.5, weekly: 38 + Double(i) / 3)
        }
        render(HistoryChartView(samples: short, now: now), name: "chart-short-dark", scheme: .dark, to: dir)
        exit(0)
    }

    private static func render(_ content: some View, name: String, scheme: ColorScheme, to dir: URL) {
        NSApplication.shared.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let view = content
            .padding(16)
            .frame(width: 380)
            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appending(path: "\(name).png"))
        }
    }

    /// 7日分のそれらしいダミーデータ（深夜2〜8時はスリープしていて記録なし）
    private static func sampleData(now: Date) -> [UsageSample] {
        var samples: [UsageSample] = []
        var weekly = 0.0
        var session = 0.0
        var sessionStart: Date?
        var date = now.addingTimeInterval(-7 * 24 * 3600)
        var rng = SystemRandomNumberGenerator()
        while date <= now {
            let hour = Calendar.current.component(.hour, from: date)
            if (2..<8).contains(hour) {
                date.addTimeInterval(600)
                continue
            }
            if let start = sessionStart, date.timeIntervalSince(start) >= 5 * 3600 {
                session = 0
                sessionStart = nil
            }
            if Double.random(in: 0...1, using: &rng) < 0.5 {
                if sessionStart == nil { sessionStart = date }
                let delta = Double.random(in: 0...4, using: &rng)
                session = min(100, session + delta)
                weekly = min(100, weekly + delta * 0.08)
            }
            samples.append(UsageSample(date: date, session: session.rounded(), weekly: weekly.rounded()))
            date.addTimeInterval(600)
        }
        return samples
    }
}
#endif
