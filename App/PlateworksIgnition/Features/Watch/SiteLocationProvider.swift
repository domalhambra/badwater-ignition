import Foundation
import Observation
import PlateworksCore
#if canImport(CoreLocation)
import CoreLocation
#endif

/// One-shot GPS fix for the observation site — the coordinate and elevation that
/// otherwise have to be typed as decimal degrees on a fireline.
///
/// Deliberately **one-shot, not continuous**. A weather watch needs the position
/// of the site, which changes when the crew moves, not a live track: continuous
/// updates would burn battery across a 16-hour shift and keep a location stream
/// running in a tool whose whole premise is that it observes nothing about you.
/// `requestLocation()` delivers a single fix and stops.
///
/// The elevation is normalized by ``SiteElevation`` (rounded to 100 ft, checked
/// against the ``ElevationBand`` boundaries) rather than used raw, because it
/// feeds the station pressure for the sling-RH derivation and therefore the PIG.
/// A fix whose uncertainty straddles a band edge is reported as such so the crew
/// confirms it against a map instead of trusting it — see ``Fix/straddlesBandBoundary``.
///
/// Nothing here is persisted or transmitted; the fix exists only long enough for
/// the operator to accept it into the site fields, which they can then edit.
///
/// `@MainActor` like the other view models. CoreLocation delivers its callbacks
/// on the queue the manager was created on — main, since `init` is main-actor —
/// so the delegate shim below hops back with `MainActor.assumeIsolated` rather
/// than an async dispatch, keeping a fix's arrival synchronous with the UI that
/// renders it.
@MainActor
@Observable
final class SiteLocationProvider {

    /// A single accepted GPS fix, already normalized for field use.
    struct Fix: Equatable {
        /// The coordinate, validated through ``GeoPoint/init(validating:longitude:)``.
        let coordinate: GeoPoint
        /// Elevation rounded to the nearest 100 ft, or `nil` when the fix had no
        /// usable vertical component (indoors, poor sky view, simulator default).
        let elevationFeet: Int?
        /// The ± vertical uncertainty the elevation was judged by, in feet —
        /// the sensor's own accuracy floored at the rounding's ±50 ft.
        let elevationUncertaintyFeet: Int?
        /// Horizontal accuracy in feet, for the provenance caption.
        let horizontalAccuracyFeet: Int?
        /// True when the elevation's uncertainty interval spans two elevation
        /// bands — the crew should confirm the elevation against a map, because
        /// the band picks the station pressure that derives RH.
        let straddlesBandBoundary: Bool
        let takenAt: Date
    }

    /// A raw device location reading, reduced to Sendable primitives.
    ///
    /// The CoreLocation delegate arrives on a nonisolated context and has to hand
    /// its reading to this main-actor type. Crossing that boundary with a
    /// `CLLocation` would mean sending a class reference the compiler can't prove
    /// safe; reducing it to plain values first makes the hop trivially sound.
    ///
    /// It also decouples the fix-handling rules from CoreLocation entirely, so
    /// ``normalize(_:)`` is unit-testable without a device or a real `CLLocation`.
    struct LocationSample: Sendable, Equatable {
        var latitude: Double
        var longitude: Double
        var altitudeMeters: Double
        /// Non-positive means CoreLocation has no altitude for this fix.
        var verticalAccuracyMeters: Double
        var horizontalAccuracyMeters: Double
        var timestamp: Date
    }

    /// What the fix button should be showing.
    enum Status: Equatable {
        case idle
        case locating
        /// Permission was refused or restricted — the operator must enable it in
        /// Settings; the site fields stay hand-editable regardless.
        case denied
        /// A fix couldn't be obtained (services off, no sky, timeout). Carries a
        /// short reason for the status strip.
        case failed(String)
        case fixed(Fix)
    }

    private(set) var status: Status = .idle

    /// The most recent successful fix, retained after the status moves on so the
    /// site fields can show a "GPS · 14:32" provenance caption.
    private(set) var lastFix: Fix?

    #if canImport(CoreLocation)
    private let manager = CLLocationManager()
    private let delegate = Delegate()
    #endif

    init() {
        #if canImport(CoreLocation)
        // Whole-degree-scale accuracy is pointless here: the IMET sheet records
        // five decimal places (~1 m) and the elevation feeds a band decision.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.delegate = delegate
        delegate.owner = self
        #endif
    }

    /// True while a fix is in flight — the button shows a spinner and is disabled.
    var isLocating: Bool { status == .locating }

    /// Ask for a single fix, requesting permission first if it hasn't been
    /// resolved yet. Safe to call repeatedly; a second call while locating is
    /// ignored.
    func requestFix() {
        #if canImport(CoreLocation)
        guard !isLocating else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .locating
            // The fix is kicked off from the authorization callback once the
            // operator answers the prompt.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        default:
            status = .locating
            manager.requestLocation()
        }
        #else
        status = .failed("Location is unavailable on this device.")
        #endif
    }

    /// Turn a raw reading into a normalized ``Fix``, or `nil` if the coordinate
    /// isn't real.
    ///
    /// Pure, `static`, and free of CoreLocation types — so the rules that decide
    /// a fix's elevation and whether it straddles an elevation band are unit
    /// tested directly, without a device, a simulator, or a real `CLLocation`.
    static func normalize(_ sample: LocationSample) -> Fix? {
        guard let coordinate = GeoPoint(validating: sample.latitude,
                                        longitude: sample.longitude) else { return nil }

        // A non-positive verticalAccuracy means CoreLocation has no altitude for
        // this fix — take the coordinate and leave the elevation to be typed.
        let elevationFeet = sample.verticalAccuracyMeters > 0
            ? SiteElevation.roundedFeet(fromMeters: sample.altitudeMeters)
            : nil

        let uncertainty: Int?
        let straddles: Bool
        if let elevationFeet {
            let accuracyFeet = SiteElevation.feet(fromMeters: sample.verticalAccuracyMeters)
            let u = SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: accuracyFeet)
            uncertainty = u
            straddles = SiteElevation.straddlesBandBoundary(feetMSL: elevationFeet, uncertaintyFeet: u)
        } else {
            uncertainty = nil
            straddles = false
        }

        return Fix(
            coordinate: coordinate,
            elevationFeet: elevationFeet,
            elevationUncertaintyFeet: uncertainty,
            horizontalAccuracyFeet: sample.horizontalAccuracyMeters > 0
                ? SiteElevation.feet(fromMeters: sample.horizontalAccuracyMeters).map { Int($0.rounded()) }
                : nil,
            straddlesBandBoundary: straddles,
            takenAt: sample.timestamp)
    }

    #if canImport(CoreLocation)
    fileprivate func authorizationSettled() {
        switch manager.authorizationStatus {
        case .notDetermined:
            break   // still waiting on the operator
        case .denied, .restricted:
            status = .denied
        default:
            // Permission just granted for a request already in flight.
            if isLocating { manager.requestLocation() }
        }
    }

    fileprivate func accept(_ sample: LocationSample) {
        guard let fix = Self.normalize(sample) else {
            status = .failed("The fix returned an invalid coordinate.")
            return
        }
        lastFix = fix
        status = .fixed(fix)
    }

    /// `denied` is resolved in the delegate so no `Error` (not Sendable) has to
    /// cross the isolation boundary.
    fileprivate func fail(denied: Bool) {
        if denied {
            status = .denied
            return
        }
        status = .failed("No fix — try again with a clearer view of the sky.")
    }

    /// CoreLocation's delegate has to be an `NSObject`, which doesn't mix with
    /// the `@Observable` macro, so it lives here as a thin forwarding shim.
    ///
    /// Every hop captures **only Sendable values** — never `self`. Reading
    /// `self.owner` inside the closure captured the (non-Sendable) delegate and
    /// the Swift 6 mode rejected it with "sending 'self' risks causing data
    /// races"; binding `owner` to a local first captures just that reference,
    /// which is Sendable because a `@MainActor`-isolated class is implicitly so.
    /// The reading itself is reduced to a ``LocationSample`` of plain values.
    ///
    /// `assumeIsolated` is sound because the manager is created in a main-actor
    /// `init`, so CoreLocation delivers on the main queue.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        weak var owner: SiteLocationProvider?

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last, let owner else { return }
            let sample = LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.altitude,
                verticalAccuracyMeters: location.verticalAccuracy,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                timestamp: location.timestamp)
            MainActor.assumeIsolated { owner.accept(sample) }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            guard let owner else { return }
            // Resolve the denial here so no Error crosses the boundary.
            let denied = (error as? CLError)?.code == .denied
            MainActor.assumeIsolated { owner.fail(denied: denied) }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard let owner else { return }
            MainActor.assumeIsolated { owner.authorizationSettled() }
        }
    }
    #endif
}
