import Foundation
import BadwaterCore

/// Durable storage for the observation record — the current shift and the
/// retained history.
///
/// ### Why this exists
/// Both lived in `UserDefaults` as JSON blobs. `UserDefaults` is a preferences
/// cache, read and written wholesale as a plist; `history` is *designed* to grow
/// across a whole assignment, and every appended observation re-encoded and
/// rewrote the entire structure. This is also the evidentiary record of what went
/// out over the radio net, so it deserves a real file with an atomic write.
///
/// ### Why an App Group container
/// The obvious home is Application Support. It is the wrong one: a **widget
/// extension is a separate process and cannot read the app's private
/// container**. Writing to an App Group from the start means the record is
/// migrated once rather than twice, and each migration of a live shift log is a
/// chance to lose one.
///
/// The group container is unavailable when the entitlement isn't provisioned —
/// notably in CI, which builds with `CODE_SIGNING_ALLOWED=NO`. The fallback to
/// Application Support is therefore a real, exercised path, not a nicety.
///
/// > Note: an App Group is shared with *extensions on the same device*. It does
/// > not reach a paired watch, which has its own storage — a watchOS app needs
/// > `WatchConnectivity` regardless.
///
/// ### Migration
/// On first use the legacy `UserDefaults` blobs are read and written out as
/// files. The legacy keys are deliberately **left in place** for at least one
/// release: if a build has to be rolled back, the record is still there. Nothing
/// is ever re-rendered during a migration — `broadcastText` in particular is
/// carried across verbatim, because it is the record of what was actually spoken.
@MainActor
final class ObservationRecordStore {

    /// Shared container identifier. Must match the App Group entitlement.
    static let appGroupIdentifier = "group.com.badwater.ignition"

    /// Legacy `UserDefaults` keys, still read for migration and still written by
    /// nothing. Kept for rollback safety.
    enum LegacyKeys {
        static let shift = "watch.shift"
        static let history = "watch.history"
    }

    private enum Filename {
        static let shift = "shift.json"
        static let history = "history.json"
    }

    private let directory: URL?
    private let defaults: UserDefaults

    /// True when a write has failed. The in-memory record is unaffected; the
    /// screen uses this to tell the crew to export before quitting.
    private(set) var writeFailed = false

    /// - Parameters:
    ///   - defaults: source of the legacy blobs to migrate from.
    ///   - directory: override for tests. When `nil`, the App Group container is
    ///     used, falling back to Application Support when it isn't provisioned.
    init(defaults: UserDefaults, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? Self.defaultDirectory()
        migrateIfNeeded()
    }

    // MARK: - Locations

    private static func defaultDirectory() -> URL? {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return ensured(group.appendingPathComponent("Record", isDirectory: true))
        }
        // No entitlement (CI, or a build without the group provisioned): keep the
        // record on-device in Application Support rather than losing it.
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil, create: true) else { return nil }
        return ensured(support.appendingPathComponent("BadwaterIgnition", isDirectory: true))
    }

    private static func ensured(_ url: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }

    private func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    // MARK: - Migration

    /// Copy the legacy `UserDefaults` blobs into files, once.
    ///
    /// Idempotent by construction: it only writes a file that does not already
    /// exist, so a second run is a no-op and cannot duplicate or truncate a
    /// record. The legacy keys are left untouched.
    private func migrateIfNeeded() {
        migrate(legacyKey: LegacyKeys.shift, to: Filename.shift, as: Shift.self)
        migrate(legacyKey: LegacyKeys.history, to: Filename.history, as: [Shift].self)
    }

    private func migrate<T: Codable>(legacyKey: String, to filename: String, as type: T.Type) {
        guard let url = url(filename),
              !FileManager.default.fileExists(atPath: url.path),
              let legacy = defaults.data(forKey: legacyKey) else { return }
        // Decode before writing: a blob that can't be decoded is not a record,
        // and copying it forward would only move the problem.
        guard let decoded = try? JSONDecoder().decode(T.self, from: legacy) else { return }
        write(decoded, to: filename)
    }

    // MARK: - Read

    func loadShift() -> Shift? { read(Shift.self, from: Filename.shift) }
    func loadHistory() -> [Shift] { read([Shift].self, from: Filename.history) ?? [] }

    private func read<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        guard let url = url(filename), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Write

    @discardableResult
    func saveShift(_ shift: Shift) -> Bool { write(shift, to: Filename.shift) }

    @discardableResult
    func saveHistory(_ history: [Shift]) -> Bool { write(history, to: Filename.history) }

    /// Encode and write atomically.
    ///
    /// `.atomic` writes to a temporary file and renames, so an interrupted write
    /// leaves the *previous* good file intact rather than a truncated one — which
    /// matters when the thing being written is the log of what went out on the
    /// radio. A failure sets ``writeFailed`` and leaves the last good file alone;
    /// it never destroys what it couldn't replace.
    @discardableResult
    private func write<T: Encodable>(_ value: T, to filename: String) -> Bool {
        guard let url = url(filename) else {
            writeFailed = true
            return false
        }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            return true
        } catch {
            writeFailed = true
            return false
        }
    }
}
