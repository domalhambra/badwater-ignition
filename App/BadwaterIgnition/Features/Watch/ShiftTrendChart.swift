import SwiftUI
import Charts
import BadwaterCore

/// A compact sparkline of a selected metric across the shift's observations — the
/// output crews watch move through the afternoon. Chronological, so a back-filled
/// obs can't kink the line (the model already sorts by timestamp). The Y domain
/// is supplied by the caller so percent metrics pin to 0–100 while temperature /
/// dew point auto-fit to their range.
struct ShiftTrendChart: View {
    let points: [TrendPoint]
    var domain: ClosedRange<Int> = 0...100
    var unit: String = "%"

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Time", p.date), y: .value("Value", p.value))
                .foregroundStyle(LinearGradient(
                    colors: [BadwaterColor.accent.opacity(0.22), BadwaterColor.accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                .foregroundStyle(BadwaterColor.accent)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Time", p.date), y: .value("Value", p.value))
                .foregroundStyle(BadwaterColor.accent)
                .symbolSize(20)
        }
        .chartYScale(domain: domain)
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartYAxisLabel(unit)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 120)
        .accessibilityIdentifier("shift-trend")
    }
}

/// One plotted observation — unshaded PIG at a timestamp. `id` is the timestamp
/// so Chart keeps a stable identity across live updates.
struct TrendPoint: Identifiable {
    let date: Date
    let value: Int
    var id: Date { date }
}
