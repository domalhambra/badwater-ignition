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
    static let defaultsStore: UserDefaults = {
        guard ProcessInfo.processInfo.arguments.contains(resetStateArgument) else {
            return .standard
        }
        // A per-process suite name keeps concurrent simulator clones isolated.
        let name = "com.badwater.ignition.uitest.\(ProcessInfo.processInfo.processIdentifier)"
        guard let suite = UserDefaults(suiteName: name) else { return .standard }
        suite.removePersistentDomain(forName: name)
        return suite
    }()
}
