import Foundation
import Observation
import BadwaterCore
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
/// Deliberately **not** `@MainActor`, matching `IgnitionModel` and
/// `WeatherWatchModel`. Delegate callbacks hop to the main queue explicitly
/// instead, so every mutation of the observable `status` happens on main without
/// this one type having isolation the other models don't. Annotating all three
/// together — and moving the core to the Swift 6 language mode — is tracked as a
/// single piece of work in `docs/RED_TEAM.md` (R4).
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
        delegate.onLocation = { [weak self] location in self?.accept(location) }
        delegate.onFailure = { [weak self] error in self?.fail(error) }
        delegate.onAuthorizationChange = { [weak self] in self?.authorizationSettled() }
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

    /// Discard the current fix and its provenance — the operator has taken the
    /// site over by hand.
    func clearFix() {
        lastFix = nil
        status = .idle
    }

    #if canImport(CoreLocation)
    private func authorizationSettled() {
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

    private func accept(_ location: CLLocation) {
        guard let coordinate = GeoPoint(validating: location.coordinate.latitude,
                                        longitude: location.coordinate.longitude) else {
            status = .failed("The fix returned an invalid coordinate.")
            return
        }

        // A non-positive verticalAccuracy means CoreLocation has no altitude for
        // this fix — take the coordinate and leave the elevation to be typed.
        let hasVertical = location.verticalAccuracy > 0
        let elevationFeet = hasVertical
            ? SiteElevation.roundedFeet(fromMeters: location.altitude)
            : nil

        let uncertainty: Int?
        let straddles: Bool
        if let elevationFeet {
            let accuracyFeet = SiteElevation.feet(fromMeters: location.verticalAccuracy)
            let u = SiteElevation.effectiveUncertaintyFeet(sensorAccuracyFeet: accuracyFeet)
            uncertainty = u
            straddles = SiteElevation.straddlesBandBoundary(feetMSL: elevationFeet, uncertaintyFeet: u)
        } else {
            uncertainty = nil
            straddles = false
        }

        let fix = Fix(
            coordinate: coordinate,
            elevationFeet: elevationFeet,
            elevationUncertaintyFeet: uncertainty,
            horizontalAccuracyFeet: location.horizontalAccuracy > 0
                ? SiteElevation.feet(fromMeters: location.horizontalAccuracy).map { Int($0.rounded()) }
                : nil,
            straddlesBandBoundary: straddles,
            takenAt: location.timestamp)
        lastFix = fix
        status = .fixed(fix)
    }

    private func fail(_ error: Error) {
        // A denial can also surface as an error rather than an authorization change.
        if let clError = error as? CLError, clError.code == .denied {
            status = .denied
            return
        }
        status = .failed("No fix — try again with a clearer view of the sky.")
    }

    /// CoreLocation's delegate has to be an `NSObject`, which doesn't mix with
    /// the `@Observable` macro, so it lives here as a thin forwarding shim.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        var onLocation: ((CLLocation) -> Void)?
        var onFailure: ((Error) -> Void)?
        var onAuthorizationChange: (() -> Void)?

        // CoreLocation delivers on the queue the manager was created on, which is
        // main here — but these hop explicitly rather than rely on that, since
        // every one of them mutates observable state SwiftUI reads.
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else { return }
            DispatchQueue.main.async { [onLocation] in onLocation?(location) }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            DispatchQueue.main.async { [onFailure] in onFailure?(error) }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            DispatchQueue.main.async { [onAuthorizationChange] in onAuthorizationChange?() }
        }
    }
    #endif
}
