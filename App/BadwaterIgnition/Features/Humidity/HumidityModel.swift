import Foundation
import Observation
import BadwaterCore

/// View model for the Humidity (RH / dew point) screen.
///
/// Inputs are the dry-bulb and wet-bulb temperatures read from a sling
/// psychrometer or belt weather kit, plus the elevation band (which sets the
/// station pressure) and an Alaska toggle for the shifted thresholds. The result
/// updates live and can be chained into the Ignition screen.
@MainActor
@Observable
final class HumidityModel {
    var dryBulbF: Int { didSet { clampWet(); persist() } }
    /// Clamped on edit too, so a wet bulb typed above the dry bulb can't produce
    /// a physically impossible >100% RH.
    var wetBulbF: Int { didSet { clampWet(); persist() } }
    var band: ElevationBand { didSet { persist() } }
    var alaska: Bool { didSet { persist() } }

    private let store: UserDefaults
    init(store: UserDefaults = .standard) {
        self.store = store
        dryBulbF = store.object(forKey: Keys.dry) as? Int ?? 80
        wetBulbF = store.object(forKey: Keys.wet) as? Int ?? 60
        band = ElevationBand(rawValue: store.object(forKey: Keys.band) as? Int ?? 3) ?? .band3
        alaska = store.bool(forKey: Keys.alaska)
        clampWet()
    }

    /// The live psychrometric result.
    var result: HumidityResult {
        Psychrometrics.compute(dryBulbF: dryBulbF, wetBulbF: wetBulbF, band: band)
    }

    /// Elevation label for a band, respecting the Alaska toggle. Used by the
    /// band picker to label each option.
    func label(for band: ElevationBand) -> String {
        alaska ? band.alaskaLabel : band.conusLabel
    }

    private func clampWet() { if wetBulbF > dryBulbF { wetBulbF = dryBulbF } }

    private func persist() {
        store.set(dryBulbF, forKey: Keys.dry)
        store.set(wetBulbF, forKey: Keys.wet)
        store.set(band.rawValue, forKey: Keys.band)
        store.set(alaska, forKey: Keys.alaska)
    }

    private enum Keys {
        static let dry = "humidity.dryBulbF"
        static let wet = "humidity.wetBulbF"
        static let band = "humidity.band"
        static let alaska = "humidity.alaska"
    }
}
