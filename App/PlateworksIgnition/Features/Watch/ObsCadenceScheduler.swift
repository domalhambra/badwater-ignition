import Foundation
import PlateworksCore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules the "next observation is due" reminder.
///
/// The Obs screen already counts down to the next hourly observation, but that
/// only works while the app is foregrounded — which undercuts the point. A
/// weather watch is a *prospective* discipline: the value is in taking the obs
/// on time, not in noticing an hour later that you didn't.
///
/// ### What it deliberately does not say
/// The notification is **advisory, never authoritative**. It says an observation
/// is due; it never quotes a PIG, an FFM, or any computed value. A number
/// presented on a lock screen is a number stripped of the disclaimer, the
/// freshness strip, the band-edge marker, and everything else the screen uses to
/// keep a computed estimate honest. "Take a reading" needs none of that context;
/// "PIG 80" would.
///
/// ### Permission
/// Asked at the point of value — the first time an observation is logged — not
/// on a cold launch before the operator knows what the app does.
@MainActor
final class ObsCadenceScheduler {

    /// Abstracts `UNUserNotificationCenter` so the scheduling *decisions* are
    /// testable without a device, an entitlement, or a real notification centre.
    ///
    /// `@MainActor` because every conformer is: the scheduler itself is
    /// main-actor isolated and only ever calls these from there, and a
    /// nonisolated requirement can't be satisfied by a main-actor method.
    @MainActor
    protocol Center {
        func requestAuthorization() async -> Bool
        func removePending(identifiers: [String])
        func schedule(identifier: String, title: String, body: String, after seconds: TimeInterval)
    }

    /// The single pending reminder's identifier. One at a time: a weather watch
    /// has exactly one "next obs", and replacing it is simpler to reason about
    /// than reconciling a queue.
    static let requestIdentifier = "plateworks.obs.due"

    /// Standard hourly weather-watch cadence, matching the on-screen strip.
    ///
    /// Defined once in the core, because the countdown on the Obs screen, this
    /// reminder, the widget and the watch complication all mean the same
    /// interval by it — and because it is also the threshold at which a logged
    /// reading is superseded (see ``ObsGlance``). Two copies of this number
    /// would eventually disagree about when a number stops being showable.
    static let cadence: TimeInterval = ObsGlance.standardCadence

    private let center: Center
    private(set) var authorized = false
    private(set) var didRequestAuthorization = false

    init(center: Center) {
        self.center = center
    }

    /// The delay from `now` until the observation after `lastObs` is due, or
    /// `nil` when it is already due (or overdue) and a reminder would fire in the
    /// past.
    ///
    /// Pure and static so the timing rule is directly testable.
    static func delayUntilNextObs(after lastObs: Date, now: Date,
                                  cadence: TimeInterval = cadence) -> TimeInterval? {
        let due = lastObs.addingTimeInterval(cadence)
        let delay = due.timeIntervalSince(now)
        return delay > 0 ? delay : nil
    }

    /// Ask for permission, once, at the point of value.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        guard !didRequestAuthorization else { return authorized }
        didRequestAuthorization = true
        authorized = await center.requestAuthorization()
        return authorized
    }

    /// Re-schedule the reminder for the shift's current state.
    ///
    /// Called after every mutation that can move "the next obs": log, edit,
    /// delete, undo, and starting a new shift. Always clears the pending request
    /// first, so a deleted or corrected observation can't leave a stale reminder
    /// pointing at a time that no longer exists.
    ///
    /// - Parameter latestObs: the chronologically latest logged observation, or
    ///   `nil` when the shift is empty (nothing to remind about yet — the screen
    ///   already says "take one now").
    func reschedule(latestObs: Date?, now: Date = Date()) {
        center.removePending(identifiers: [Self.requestIdentifier])
        guard authorized,
              let latestObs,
              let delay = Self.delayUntilNextObs(after: latestObs, now: now) else { return }
        center.schedule(
            identifier: Self.requestIdentifier,
            title: "Weather observation due",
            // No computed values here — see the type note.
            body: "The next hourly obs is due. Take a reading and log it.",
            after: delay)
    }

    /// Drop any pending reminder — the shift is over.
    func cancel() {
        center.removePending(identifiers: [Self.requestIdentifier])
    }
}

#if canImport(UserNotifications)
/// The real `UNUserNotificationCenter` behind ``ObsCadenceScheduler/Center``.
@MainActor
struct SystemNotificationCenter: ObsCadenceScheduler.Center {

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func schedule(identifier: String, title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
#endif
