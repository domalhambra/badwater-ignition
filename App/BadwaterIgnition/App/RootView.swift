import SwiftUI

/// Three-tab shell: Ignition (PIG / FFM), Humidity (RH / dew point), and Watch
/// (the shift observation log). The Humidity screen can push its result into
/// Ignition and switch tabs.
///
/// All three tabs share a single ``IgnitionModel`` so the weather Watch freezes
/// is the same weather the operator sees on Ignition — constructed here in
/// `init` because one `@State` can't be initialized from another inline.
struct RootView: View {
    @State private var ignition: IgnitionModel
    @State private var humidity: HumidityModel
    @State private var watch: WeatherWatchModel
    @State private var selection: Tab = .ignition

    enum Tab: Hashable { case ignition, humidity, watch }

    init() {
        let ignition = IgnitionModel()
        _ignition = State(initialValue: ignition)
        _humidity = State(initialValue: HumidityModel())
        _watch = State(initialValue: WeatherWatchModel(ignition: ignition))
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                IgnitionView(model: ignition)
            }
            .tabItem { Label("Ignition", systemImage: "flame") }
            .tag(Tab.ignition)

            NavigationStack {
                HumidityView(model: humidity) { rh in
                    ignition.applyHumidity(rh)
                    selection = .ignition
                }
            }
            .tabItem { Label("Humidity", systemImage: "humidity") }
            .tag(Tab.humidity)

            NavigationStack {
                WatchView(model: watch, ignition: ignition)
            }
            .tabItem { Label("Watch", systemImage: "binoculars") }
            .tag(Tab.watch)
        }
        .tint(BadwaterColor.accent)
    }
}

#Preview {
    RootView()
}
