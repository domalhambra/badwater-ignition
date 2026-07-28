import Foundation

/// Process-level wiring decided once at launch.
enum AppEnvironment {

    /// Launch argument that makes the app persist into a throwaway store.
    ///
    /// UI tests run against a real simulator container, so without this every
    /// test inherits whatever the previous test left behind — and this app
    /// persists almost everything: the shift log, the retained history, the site
    /// factors, the weather inputs. `testWatchTabLogsAnObservation` logs an
    /// observation, which is exactly the state that makes the empty-state
    /// assertion in the *next* run fail. Order-dependent, machine-dependent, and
    /// invisible until the suite actually runs somewhere clean.
    static let resetStateArgument = "-uiTestingResetState"

    /// The `UserDefaults` the view models persist into.
    ///
    /// `static let`, so the throwaway suite is created **once per process**: a
    /// fresh suite per call would silently discard state whenever SwiftUI
    /// re-initialized a view that builds a model.
    ///
    /// `nonisolated(unsafe)` because `UserDefaults` is not annotated `Sendable`,
    /// which the Swift 6 language mode rejects for a global. It is documented as
    /// thread-safe by Apple, and this binding is an immutable `let` assigned once
    /// at first access — the compiler simply can't see that. Marking it rather
    /// than isolating it to the main actor keeps it usable as a default argument.
    nonisolated(unsafe) static let defaultsStore: UserDefaults = {
        guard ProcessInfo.processInfo.arguments.contains(resetStateArgument) else {
            return .standard
        }
        // A per-process suite name keeps concurrent simulator clones isolated.
        let name = "org.plateworks.ignition.uitest.\(ProcessInfo.processInfo.processIdentifier)"
        guard let suite = UserDefaults(suiteName: name) else { return .standard }
        suite.removePersistentDomain(forName: name)
        return suite
    }()

    /// Where an App Intent wants the app to land when it opens it.
    enum DeepLink {
        case logObservation
    }

    /// Set by ``LogObservationIntent`` immediately before the app is brought
    /// forward, and consumed once by ``RootView``.
    ///
    /// A plain main-actor global rather than a notification or a URL: both ends
    /// run on the main actor in the same process, the value is read exactly once
    /// on the next `onAppear`, and there is no state to keep in sync.
    @MainActor static var pendingDeepLink: DeepLink?
}
