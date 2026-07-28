import Foundation
import PlateworksCore

/// Read-only access to the observation record, for the widget extension.
///
/// Deliberately **not** `ObservationRecordStore`: that type migrates and writes,
/// and a widget must do neither. Read-only here is a property of the type rather
/// than a convention someone has to remember — there is no code path from a
/// widget to a mutated record, so the display policy's "no surface outside the
/// app creates an observation" cannot be violated by accident.
///
/// It also does **not** inherit the app's Application Support fallback. When the
/// App Group entitlement isn't provisioned the reader returns `nil` and the
/// widget shows "No obs logged". An extension has no business inventing a
/// location, and an empty widget is a far better failure than one confidently
/// rendering a stale file the app never writes to.
enum RecordReader {

    /// The shift's chronologically latest observation, or `nil` when there is no
    /// record, no entitlement, or nothing logged yet.
    ///
    /// `Shift.latest` is the chronological maximum, not the last appended, so a
    /// back-filled observation cannot masquerade as current on the home screen.
    static func latestObservation() -> WeatherObs? {
        guard let container = RecordLocation.groupContainer() else { return nil }
        let url = container.appendingPathComponent(RecordLocation.shiftFilename)
        guard let data = try? Data(contentsOf: url),
              let shift = try? JSONDecoder().decode(Shift.self, from: data) else { return nil }
        return shift.latest
    }

    /// The shift's division / location label, for context on the widget.
    static func siteLabel() -> String? {
        guard let container = RecordLocation.groupContainer() else { return nil }
        let url = container.appendingPathComponent(RecordLocation.shiftFilename)
        guard let data = try? Data(contentsOf: url),
              let shift = try? JSONDecoder().decode(Shift.self, from: data) else { return nil }
        return shift.division ?? shift.locationName
    }
}
