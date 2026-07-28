import Foundation
import PlateworksCore

/// Where the watch keeps the last snapshot the phone sent.
///
/// ### Why this exists at all
/// Task 14 of the plan lists the App Group on the phone app and its widget, and
/// notes the watch can't reach it — true, and it leaves a gap the plan doesn't
/// close: the **complication is a separate process from the watch app**, so it
/// cannot read the receiver's in-memory state either. It needs a file, in a
/// container both watch targets can open.
///
/// So the watch pair gets its own App Group. It is a different identifier from
/// the phone's on purpose — nothing is shared across the pairing, and reusing
/// the phone's identifier would suggest otherwise to the next reader.
///
/// ### It stores a snapshot, never a glance
/// Whether a reading is still showable is re-decided against the reading
/// device's own clock every time something draws — see
/// ``WatchSnapshot/glance(at:)``. A stored glance would be a frozen verdict
/// about freshness, which is exactly the thing that must not be frozen.
enum WatchSnapshotStore {

    /// Must match the App Group entitlement on the watch app **and** the
    /// complication. Distinct from the phone's `group.org.plateworks.ignition`:
    /// an App Group is shared between a host app and its extensions on one
    /// device, and does not cross the pairing.
    static let appGroupIdentifier = "group.org.plateworks.ignition.watch"

    static let filename = "snapshot.json"

    /// The container, falling back to Application Support when the entitlement
    /// isn't provisioned — which is the case in CI, and on any build without
    /// the group. The watch app still works from the fallback; only the
    /// complication goes blank, because the two processes no longer share a
    /// directory. That is the honest failure and it is visible immediately.
    static func directory() -> URL? {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return ensured(group.appendingPathComponent("Record", isDirectory: true))
        }
        guard let support = try? fm.url(for: .applicationSupportDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil, create: true) else { return nil }
        return ensured(support.appendingPathComponent("PlateworksWatch", isDirectory: true))
    }

    private static func ensured(_ url: URL) -> URL? {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load() -> WatchSnapshot? {
        guard let url = directory()?.appendingPathComponent(filename),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    /// Persist, or clear when `snapshot` is `nil` — an empty context from the
    /// phone means the shift ended or its last observation was deleted, and the
    /// complication must stop showing a reading the phone no longer has.
    static func save(_ snapshot: WatchSnapshot?) {
        guard let url = directory()?.appendingPathComponent(filename) else { return }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
