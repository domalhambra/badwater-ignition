import SwiftUI

/// Three-tab shell: Humidity (RH / dew point), Ignition (PIG / FFM), and Obs
/// (the shift observation log — the Weather-Watch feature, ``WatchView`` /
/// ``WeatherWatchModel`` internally). The Humidity screen can push its result
/// into Ignition and switch tabs.
///
/// All three tabs share a single ``IgnitionModel`` so the weather the Obs tab
/// freezes is the same weather the operator sees on Ignition — constructed here in
/// `init` because one `@State` can't be initialized from another inline.
@MainActor
struct RootView: View {
    @State private var ignition: IgnitionModel
    @State private var humidity: HumidityModel
    @State private var watch: WeatherWatchModel
    @State private var selection: Tab = .ignition

    enum Tab: Hashable { case ignition, humidity, watch }

    /// - Parameter store: where the models persist. Defaults to
    ///   ``AppEnvironment/defaultsStore``, which is `.standard` in normal use and
    ///   a throwaway suite when the UI tests pass their reset flag, so each test
    ///   starts from first-launch defaults instead of inheriting the previous
    ///   test's shift log.
    init(store: UserDefaults = AppEnvironment.defaultsStore) {
        let ignition = IgnitionModel(store: store)
        _ignition = State(initialValue: ignition)
        _humidity = State(initialValue: HumidityModel(store: store))
        _watch = State(initialValue: WeatherWatchModel(ignition: ignition, store: store))
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HumidityView(model: humidity) { rh in
                    ignition.applyHumidity(rh)
                    selection = .ignition
                }
            }
            .tabItem { Label("Humidity", systemImage: "humidity") }
            .tag(Tab.humidity)

            NavigationStack {
                IgnitionView(model: ignition)
            }
            .tabItem { Label("Ignition", systemImage: "flame") }
            .tag(Tab.ignition)

            NavigationStack {
                WatchView(model: watch, ignition: ignition)
            }
            .tabItem { Label("Obs", systemImage: "binoculars") }
            .tag(Tab.watch)
        }
        .tint(BadwaterColor.accent)
    }
}

#Preview {
    RootView()
}
