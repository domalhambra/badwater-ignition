import SwiftUI

/// The watchOS app: a **read-only mirror** of the phone's latest logged
/// observation.
///
/// There is no capture card here and there never will be while the display
/// policy holds — freezing a reading requires the app on the phone, so nothing
/// on the wrist can create an observation. That is what makes the whole watch
/// side a one-way projection rather than a two-way sync, and why there is no
/// merge problem to solve.
@main
struct BadwaterWatchApp: App {

    @State private var receiver = WatchSessionReceiver()

    var body: some Scene {
        WindowGroup {
            WatchGlanceView(receiver: receiver)
        }
    }
}
