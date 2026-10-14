import AppKit
import Charts
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "24時間"
    case week = "7日"

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        }
    }
}

enum UsageSeries: String, CaseIterable {
    case session = "セッション"
    case weekly = "今週"

    /// ライト/ダークそれぞれの背景で見やすい色を使い分ける
    var color: Color {
        switch self {
        case .session: .adaptive(light: 0x2A78D6, dark: 0x3987E5)
        case .weekly: .adaptive(light: 0xEB6834, dark: 0xD95926)
        }
    }

    func value(of sample: UsageSample) -> Double? {
        switch self {
        case .session: sample.session
        case .weekly: sample.weekly
        }
    }
}

struct HistoryChartView: View {
    let samples: [UsageSample]
    var thresholds = Thresholds.defaults
    var now = Date()
    /// 画像の書き出しでは期間の切り替え（AppKit の部品で画像にできない）を隠す
    var showsRangePicker = true

    @AppStorage("historyRange") private var range: HistoryRange = .day
    @State private var hoverDate: Date?

    /// この時間以上記録が空いたら（スリープ中など）線をつながない
    private let gapThreshold: TimeInterval = 30 * 60

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        let series: UsageSeries
        let segment: Int
        var id: String { "\(series.rawValue)-\(date.timeIntervalSince1970)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                readout
                Spacer()
                if showsRangePicker {
                    Picker("期間", selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            // 点の数ではなく記録の件数で判定する（1件の記録でもセッションと今週で点は2つになるため）
            if visibleSamples.count < 2 {
                Text("記録中です。10分ほどでグラフが表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart.frame(height: 120)
                if axis.isZoomed, let first = visibleSamples.first {
                    Text("\(timeFormatter.string(from: first.date)) から記録中（記録のある範囲を拡大表示）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
    }

    // MARK: - 凡例 / ホバー中の値

    /// 普段は凡例、マウスを乗せている間はその時刻の値を表示する
    private var readout: some View {
        HStack(spacing: 10) {
            if let hovered {
                Text(hovered.date, format: .dateTime.month(.defaultDigits).day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            ForEach(UsageSeries.allCases, id: \.self) { series in
                HStack(spacing: 4) {
                    Circle().fill(series.color).frame(width: 7, height: 7)
                    Text(series.rawValue)
                    if let hovered {
                        Text(series.value(of: hovered).map { "\(Int($0.rounded()))%" } ?? "–")
                            .monospacedDigit()
                    }
                }
            }
        }
        .font(.caption)
    }

    // MARK: - グラフ本体

    private var chart: some View {
        Chart {
            // 通知の段階の目安
            ForEach(thresholds, id: \.self) { threshold in
                RuleMark(y: .value("通知", threshold))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("時刻", point.date),
                    y: .value("使用率", point.value),
                    series: .value("系列", "\(point.series.rawValue)-\(point.segment)")
                )
                .foregroundStyle(point.series.color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            // スリープ明けなどで1点だけになった区間は線にならないので、点で見せる
            ForEach(isolatedPoints) { point in
                PointMark(x: .value("時刻", point.date), y: .value("使用率", point.value))
                    .foregroundStyle(point.series.color)
                    .symbolSize(16)
            }

            if let hovered {
                RuleMark(x: .value("時刻", hovered.date))
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(UsageSeries.allCases, id: \.self) { series in
                    if let value = series.value(of: hovered) {
                        PointMark(x: .value("時刻", hovered.date), y: .value("使用率", value))
                            .foregroundStyle(series.color)
                            .symbolSize(50)
                    }
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: axis.domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.25))
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartXAxis {
            AxisMarks(values: axis.ticks) { _ in
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.15))
                if axis.usesDayLabels {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                } else {
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            hoverDate = proxy.value(atX: x)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
    }

    // MARK: - データ

    private var axis: ChartTimeAxis {
        // 「表示範囲の中で最初の記録」ではなく「記録全体で最初」を見る。
        // そうしないと、夜間のスリープで記録が空いただけでも拡大してしまう
        ChartTimeAxis.make(range: range, firstSample: samples.first?.date, now: now)
    }

    private var visibleSamples: [UsageSample] {
        let domain = axis.domain
        return samples.filter { domain.contains($0.date) }
    }

    private var points: [Point] {
        var result: [Point] = []
        var segment = 0
        var previous: Date?
        for sample in visibleSamples {
            if let previous, sample.date.timeIntervalSince(previous) > gapThreshold {
                segment += 1
            }
            previous = sample.date
            for series in UsageSeries.allCases {
                if let value = series.value(of: sample) {
                    result.append(Point(date: sample.date, value: value, series: series, segment: segment))
                }
            }
        }
        return result
    }

    private var isolatedPoints: [Point] {
        let all = points
        var counts: [String: Int] = [:]
        for point in all { counts["\(point.series.rawValue)-\(point.segment)", default: 0] += 1 }
        return all.filter { counts["\($0.series.rawValue)-\($0.segment)"] == 1 }
    }

    /// マウス位置にいちばん近い記録
    private var hovered: UsageSample? {
        guard let hoverDate else { return nil }
        return visibleSamples.min {
            abs($0.date.timeIntervalSince(hoverDate)) < abs($1.date.timeIntervalSince(hoverDate))
        }
    }
}

/// グラフの横軸（表示範囲と目盛り）。UIに依存しないのでテストしやすい
struct ChartTimeAxis {
    let domain: ClosedRange<Date>
    let ticks: [Date]
    /// 目盛りが1日ごとなら曜日、それより細かければ時刻を表示する
    let usesDayLabels: Bool
    /// 記録が期間より短いので、記録のある範囲に寄せて拡大している
    let isZoomed: Bool

    /// 拡大するときも、最低これだけの幅は見せる
    static let minimumSpan: TimeInterval = 3 * 3600

    static func make(range: HistoryRange, firstSample: Date?, now: Date, calendar: Calendar = .current) -> ChartTimeAxis {
        let fullStart = now.addingTimeInterval(-range.duration)
        var start = fullStart
        var isZoomed = false
        // 記録を始めたばかりだと、24時間の幅では右端に小さく縮こまってしまう
        if let firstSample, firstSample > fullStart {
            start = min(firstSample, now.addingTimeInterval(-minimumSpan))
            isZoomed = start > fullStart
        }

        // 目盛りが5本程度に収まる間隔を選ぶ
        let span = now.timeIntervalSince(start)
        let stepHours = [1, 2, 3, 6, 12].first { span / Double($0 * 3600) <= 5 } ?? 24

        // 端に近すぎる目盛りはラベルが切れて「…」になるので出さない
        let margin = span * 0.07
        var ticks: [Date] = []
        var tick = calendar.startOfDay(for: start)
        while tick <= now {
            if tick >= start.addingTimeInterval(margin), tick <= now.addingTimeInterval(-margin) {
                ticks.append(tick)
            }
            guard let next = calendar.date(byAdding: .hour, value: stepHours, to: tick) else { break }
            tick = next
        }
        return ChartTimeAxis(domain: start...now, ticks: ticks, usesDayLabels: stepHours >= 24, isZoomed: isZoomed)
    }
}
