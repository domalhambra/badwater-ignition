import AppIntents
import PlateworksCore

/// Siri / Shortcuts / Action Button entry points.
///
/// The posture on a line is hands-busy: gloves on, a tool in one hand, the phone
/// in a chest pocket. Voice and a hardware button are the right affordances.
///
/// ### The one design decision that matters here
/// **Logging an observation opens the app; it does not log silently.**
///
/// That looks like the weaker choice and is the safer one. `WeatherWatchModel`
/// gates the first log of a shift on an explicit site review, precisely so a
/// persisted default aspect or elevation can never silently feed a broadcast.
/// A voice command that froze a reading in the background would walk straight
/// past that gate, and would freeze whatever weather happened to be left on the
/// Ignition tab — possibly hours old — into the evidentiary record. So the log
/// intent brings the operator to the capture card with everything visible, which
/// is still a large win over finding and opening the app by hand.
///
/// Reading the current estimate has no such hazard and answers in place.
@available(iOS 17.0, macOS 14.0, *)
struct CurrentIgnitionIntent: AppIntent {
    static let title: LocalizedStringResource = "Current probability of ignition"
    static let description = IntentDescription(
        "Reads the Probability of Ignition for the weather currently entered in Plateworks Ignition.")

    /// Answers in place — nothing here mutates the record.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = IgnitionModel(store: AppEnvironment.defaultsStore)
        let estimate = model.estimate
        let unshaded = estimate.unshaded
        let behavior = unshaded.interpretation

        // Spoken as the screen frames it: both shadings, the band, and the
        // standing caveat that this is computed rather than observed. A spoken
        // number with no caveat is the same hazard as a number on a lock screen.
        let dialog = IntentDialog(
            """
            Probability of ignition \(unshaded.probabilityOfIgnition) percent unshaded, \
            \(estimate.shaded.probabilityOfIgnition) percent shaded. \
            \(behavior.title). \
            Computed from \(model.dryBulbF) degrees and \(model.effectiveRelativeHumidity) percent humidity — \
            verify against your I R P G.
            """)
        return .result(dialog: dialog)
    }
}

/// Take a weather observation — opens the app at the capture card.
@available(iOS 17.0, macOS 14.0, *)
struct LogObservationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a weather observation"
    static let description = IntentDescription(
        "Opens Plateworks Ignition ready to log a weather observation.")

    /// Deliberately `true` — see the type note on ``CurrentIgnitionIntent``. The
    /// shift's site-review gate and the weather-freshness strip are both on the
    /// screen this opens, and neither can do its job if the log happens in the
    /// background.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.pendingDeepLink = .logObservation
        return .result()
    }
}

/// Phrases Siri accepts without the user configuring anything.
@available(iOS 17.0, macOS 14.0, *)
struct PlateworksShortcuts: AppShortcutsProvider {
    // `static let`/computed rather than `static var`: under the Swift 6 language
    // mode a mutable static is global shared mutable state and is rejected. The
    // AppIntents requirements are all `{ get }`, so this satisfies them.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CurrentIgnitionIntent(),
            phrases: [
                "What's the \(.applicationName) probability of ignition",
                "Check \(.applicationName)",
                "\(.applicationName) P I G"
            ],
            shortTitle: "Current PIG",
            systemImageName: "flame")
        AppShortcut(
            intent: LogObservationIntent(),
            phrases: [
                "Log a \(.applicationName) observation",
                "Take a \(.applicationName) weather obs"
            ],
            shortTitle: "Log observation",
            systemImageName: "binoculars")
    }
}
