import Foundation
import Observation
import BadwaterCore

/// View model for the Ignition (PIG / FFM) screen.
///
/// Temperature and humidity are the fast-changing inputs; the site factors
/// (aspect, slope, elevation delta) persist between launches because they don't
/// change while a crew works the same piece of line. Month and time-of-day
/// pre-fill from the device clock and can be overridden for forecasts.
///
/// Every property change recomputes ``estimate`` synchronously — the screen has
/// no "Calculate" button. All computation is local and offline.
@Observable
final class IgnitionModel {
    var dryBulbF: Int { didSet { persist() } }
    var relativeHumidity: Int { didSet { persist() } }
    var month: Int { didSet { persist() } }
    var timeOfDay: TimeOfDay { didSet { persist() } }
    var aspect: Aspect { didSet { persist() } }
    var slope: Slope { didSet { persist() } }
    var elevationDelta: ElevationDelta { didSet { persist() } }

    private let store: UserDefaults

    init(store: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) {
        self.store = store
        let comps = calendar.dateComponents([.month, .hour, .minute], from: now)
        // Fast inputs start at sensible mid-range defaults.
        dryBulbF = store.object(forKey: Keys.dryBulb) as? Int ?? 75
        relativeHumidity = store.object(forKey: Keys.rh) as? Int ?? 20
        // Month / time pre-fill from the clock unless previously overridden this session.
        month = comps.month ?? 7
        timeOfDay = TimeOfDay.from(hour: comps.hour ?? 12, minute: comps.minute ?? 0)
        // Persisted site factors.
        aspect = Aspect(rawValue: store.string(forKey: Keys.aspect) ?? "") ?? .south
        slope = Slope(rawValue: store.string(forKey: Keys.slope) ?? "") ?? .gentle
        elevationDelta = ElevationDelta(rawValue: store.string(forKey: Keys.elevation) ?? "") ?? .level
    }

    /// The live estimate for the current inputs (both shaded and unshaded).
    var estimate: IgnitionEstimate {
        IgnitionCalculator.estimate(
            IgnitionInput(
                dryBulbF: dryBulbF, relativeHumidity: relativeHumidity, month: month,
                timeOfDay: timeOfDay, aspect: aspect, slope: slope, elevationDelta: elevationDelta))
    }

    /// Seed the humidity result coming from the RH screen ("Use in ignition calc").
    func applyHumidity(_ rh: Int) { relativeHumidity = min(max(rh, 0), 100) }

    private func persist() {
        // didSet does not fire during init, so this only runs on user edits.
        store.set(dryBulbF, forKey: Keys.dryBulb)
        store.set(relativeHumidity, forKey: Keys.rh)
        store.set(aspect.rawValue, forKey: Keys.aspect)
        store.set(slope.rawValue, forKey: Keys.slope)
        store.set(elevationDelta.rawValue, forKey: Keys.elevation)
    }

    private enum Keys {
        static let dryBulb = "ignition.dryBulbF"
        static let rh = "ignition.rh"
        static let aspect = "ignition.aspect"
        static let slope = "ignition.slope"
        static let elevation = "ignition.elevationDelta"
    }
}

extension Month {
    /// Short month names for the month picker.
    static let shortNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

/// Namespace for month helpers used by the picker.
enum Month {}
