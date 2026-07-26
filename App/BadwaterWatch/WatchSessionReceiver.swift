import Foundation
import WatchConnectivity
import Observation
import WidgetKit
import BadwaterCore

/// The watch half of the mirror.
///
/// Holds the last ``WatchSnapshot`` the phone sent, and **persists it to disk**
/// so the app opens showing the last known reading rather than a blank screen
/// while it waits for a session to activate. A crew member raising a wrist
/// wants what was logged, not a spinner.
///
/// It stores the snapshot only. It never stores a *glance* — whether a reading
/// is still showable is re-decided against the watch's own clock every time the
/// screen draws (see ``WatchSnapshot/glance(at:)``), because application context
/// is delivered opportunistically and a snapshot can arrive, or be re-read from
/// disk, long after it was made.
@MainActor
@Observable
final class WatchSessionReceiver: NSObject {

    /// The latest snapshot, or `nil` when the shift is empty or nothing has
    /// arrived yet. Distinguishing "no obs" from "not synced" is deliberately
    /// not attempted — both mean the watch has no reading to show.
    private(set) var snapshot: WatchSnapshot?

    override init() {
        super.init()
        snapshot = WatchSnapshotStore.load()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ context: [String: Any]) {
        // An empty or unreadable context decodes to nil, and that is meaningful
        // rather than a failure: it is how the phone says the shift ended or its
        // last observation was deleted. Clear rather than keep showing a reading
        // the phone no longer has.
        let decoded = WatchSnapshot.from(applicationContext: context)
        snapshot = decoded
        // Written to the shared container, not just held here: the complication
        // is a separate process and this file is the only way it sees anything.
        WatchSnapshotStore.save(decoded)
        // And it has its own .never timeline, so it has to be told.
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchSessionReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        // The context that was current at activation is not delivered as a
        // didReceive callback, so read it directly or a watch that launched
        // after the phone's last send would show nothing new.
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }
}
