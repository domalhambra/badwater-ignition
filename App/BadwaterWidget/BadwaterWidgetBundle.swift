import WidgetKit
import SwiftUI

/// Every glanceable surface the phone provides.
///
/// All of them are **read-only mirrors of the frozen record**: they read the App
/// Group container through ``RecordReader``, which cannot write, and none of
/// them can create an observation. Freezing a reading requires the capture card
/// in the app — see the display policy in `CLAUDE.md`.
@main
struct BadwaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestObsWidget()
    }
}
