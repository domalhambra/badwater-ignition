import SwiftUI

/// Two-tab shell: Ignition (PIG / FFM) and Humidity (RH / dew point).
/// The Humidity screen can push its result into Ignition and switch tabs.
struct RootView: View {
    @State private var ignition = IgnitionModel()
    @State private var humidity = HumidityModel()
    @State private var selection: Tab = .ignition

    enum Tab: Hashable { case ignition, humidity }

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
        }
        .tint(BadwaterColor.accent)
    }
}

#Preview {
    RootView()
}
