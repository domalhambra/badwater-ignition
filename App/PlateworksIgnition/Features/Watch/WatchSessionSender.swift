#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import PlateworksCore

/// The phone half of the watch mirror.
///
/// ### Why `updateApplicationContext`
/// Three transports were available and two are wrong here:
///
/// - `sendMessage` needs the watch reachable *right now*. On a fire line it
///   frequently isn't, and a mirror that only works in range is not a mirror.
/// - `transferUserInfo` queues and delivers **every** item in order. The watch
///   would receive each intermediate observation of a 16-hour shift, in a
///   backlog, long after any of them mattered.
/// - `updateApplicationContext` **replaces** rather than queues. There is
///   exactly one latest observation, and a newer one makes the previous
///   irrelevant — which is precisely the semantics wanted.
///
/// ### It sends no live estimate
/// Only a frozen ``WatchSnapshot`` projected from the logged record. A watch
/// face is the most persistent glanceable surface there is; see the display
/// policy in `CLAUDE.md`.
@MainActor
final class WatchSessionSender: NSObject {

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// Mirror the shift's latest observation to the watch.
    ///
    /// Sends even when the shift is empty — an empty context is how the watch
    /// learns a shift ended or its last observation was deleted. Silently
    /// dropping that would leave a stale reading on the wrist indefinitely,
    /// which is the one outcome this whole design is built to prevent.
    func send(latest: WeatherObs?, siteLabel: String?) {
        guard let session, session.activationState == .activated else { return }
        do {
            // The wire format is defined in PlateworksCore and round-tripped
            // there, because the receiving half of it lives in a target this
            // one cannot see.
            let snapshot = WatchSnapshot.from(latest: latest, siteLabel: siteLabel)
            try session.updateApplicationContext(try snapshot?.applicationContext() ?? [:])
        } catch {
            // Nothing useful to do and nothing to tell the operator: the phone
            // remains the record of truth, and the next mutation tries again.
            // Failing loudly here would be a notification about a wrist.
        }
    }
}

extension WatchSessionSender: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    #if os(iOS)
    // Required on iOS. A watch being unpaired or swapped reactivates the
    // session against the new one; nothing here holds per-watch state.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
#endif
