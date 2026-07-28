import SwiftUI

/// Plateworks Ignition — a fast, offline field calculator for Probability of
/// Ignition, Fine Fuel Moisture, and relative humidity, built on the NWCG
/// Incident Response Pocket Guide (IRPG, PMS 461) and belt-weather-kit tables.
///
/// The calculation engine lives in the dependency-free ``PlateworksCore`` package;
/// this target is the SwiftUI presentation layer.
@main
struct PlateworksIgnitionApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
