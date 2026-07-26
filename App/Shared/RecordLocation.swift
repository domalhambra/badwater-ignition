import Foundation

/// Where the observation record lives on disk.
///
/// Extracted so the app target and the widget extension cannot disagree about
/// it. They are separate processes reading the same App Group container, and a
/// drifted identifier or filename would not present as an error — it would
/// present as "the widget is always empty", which reads like a data bug and
/// sends you looking in the wrong place. One definition, compiled into both.
enum RecordLocation {

    /// Must match the App Group entitlement on every target that reads the
    /// record. See `project.yml`: the app and the widget both declare it; the
    /// watch deliberately does not, because an App Group is shared with
    /// extensions on the same device and does not reach a paired watch.
    static let appGroupIdentifier = "group.com.badwater.ignition"

    static let shiftFilename = "shift.json"
    static let historyFilename = "history.json"

    /// The record directory inside the App Group container, or `nil` when the
    /// entitlement isn't provisioned (notably in CI, which builds with
    /// `CODE_SIGNING_ALLOWED=NO`).
    ///
    /// The app falls back to Application Support in that case — see
    /// `ObservationRecordStore`, where that fallback is a real, exercised path
    /// rather than a nicety. The **widget deliberately does not fall back**: an
    /// extension has no business inventing a location, and an empty widget is a
    /// better failure than one confidently reading a file the app never writes.
    ///
    /// Returns the URL without creating it; creation is the writer's job, and
    /// the widget never writes.
    static func groupContainer() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Record", isDirectory: true)
    }
}
