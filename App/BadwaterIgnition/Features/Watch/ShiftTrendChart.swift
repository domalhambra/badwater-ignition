import SwiftUI
import Charts
import BadwaterCore

/// A compact sparkline of the unshaded PIG across the shift's observations — the
/// headline output crews watch climb through the afternoon. Chronological, so a
/// back-filled obs can't kink the line (the model already sorts by timestamp).
struct ShiftTrendChart: View {
    let points: [TrendPoint]

    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Time", p.date), y: .value("PIG", p.value))
                .foregroundStyle(LinearGradient(
                    colors: [BadwaterColor.accent.opacity(0.22), BadwaterColor.accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", p.date), y: .value("PIG", p.value))
                .foregroundStyle(BadwaterColor.accent)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Time", p.date), y: .value("PIG", p.value))
                .foregroundStyle(BadwaterColor.accent)
                .symbolSize(20)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis { AxisMarks(values: [0, 50, 100]) }
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
