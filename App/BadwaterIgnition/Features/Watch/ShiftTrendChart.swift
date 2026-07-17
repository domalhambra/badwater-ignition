import SwiftUI
import Charts
import BadwaterCore

/// A sparkline of a selected metric, overlaying each retained **day** as its own
/// line on a shared time-of-day axis — so crews can compare how, say, RH moved at
/// 1400 today versus yesterday. Points are projected onto a common clock (the real
/// timestamp is kept for identity/sorting), the most recent day is drawn solid in
/// the brand accent with markers, and earlier days fade back (dashed). A single
/// retained day renders as one line, matching the earlier single-shift behavior.
/// The Y domain is supplied by the caller so percent metrics pin to 0–100 while
/// temperature / dew point auto-fit.
struct ShiftTrendChart: View {
    let days: [DayLine]
    var domain: ClosedRange<Int> = 0...100
    var unit: String = "%"

    var body: some View {
        Chart {
            ForEach(days) { day in
                if day.isLatest {
                    ForEach(day.points) { p in
                        AreaMark(x: .value("Time", p.clock), y: .value("Value", p.value))
                            .foregroundStyle(LinearGradient(
                                colors: [BadwaterColor.accent.opacity(0.20), BadwaterColor.accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(day.points) { p in
                    LineMark(x: .value("Time", p.clock), y: .value("Value", p.value),
                             series: .value("Day", day.label))
                        .foregroundStyle(by: .value("Day", day.label))
                        .lineStyle(StrokeStyle(lineWidth: day.isLatest ? 2.5 : 1.5,
                                               dash: day.isLatest ? [] : [4, 3]))
                        .interpolationMethod(.monotone)
                }
                if day.isLatest {
                    ForEach(day.points) { p in
                        PointMark(x: .value("Time", p.clock), y: .value("Value", p.value))
                            .foregroundStyle(BadwaterColor.accent)
                            .symbolSize(20)
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: days.map(\.label), range: styleRange)
        .chartYScale(domain: domain)
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartYAxisLabel(unit)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartLegend(days.count > 1 ? .visible : .hidden)
        .frame(height: days.count > 1 ? 150 : 120)
        .accessibilityIdentifier("shift-trend")
    }

    /// Colors mapped 1:1 onto `days` (oldest→newest): the latest day is the solid
    /// accent, earlier days step from faint to more visible muted so the ordering
    /// reads at a glance, not just from the legend.
    private var styleRange: [Color] {
        let n = max(days.count - 1, 1)
        return days.enumerated().map { i, d in
            d.isLatest
                ? BadwaterColor.accent
                : BadwaterColor.muted.opacity(0.30 + 0.35 * (Double(i) / Double(n)))
        }
    }
}

/// One plotted observation. `id` is the real timestamp (unique, stable across live
/// updates); `clock` is that timestamp projected onto a common reference day so
/// every day's line shares one time-of-day axis.
struct TrendPoint: Identifiable {
    let id: Date
    let clock: Date
    let value: Int
}

/// One day's line in the overlay.
struct DayLine: Identifiable {
    let id: Date          // start of the local day
    let label: String     // short date, e.g. "Jul 6"
    let isLatest: Bool     // the most recent retained day — drawn solid + marked
    let points: [TrendPoint]
}
