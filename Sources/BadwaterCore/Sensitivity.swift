import Foundation

/// How much a field reading might plausibly be off, in the instrument's own
/// units. The IRPG tables are step functions, so a reading a step or two from a
/// cell edge can land in a neighbouring cell and swing Probability of Ignition
/// by a whole fire-behavior band. ``SensitivityAnalysis`` perturbs the reading
/// by this envelope to tell the crew whether the displayed PIG is *firm* or
/// *sitting on an edge*.
///
/// Defaults reflect typical belt-weather-kit / Kestrel field precision, not a
/// specific instrument's spec sheet: ±2 °F on a bulb, ±3% on a directly-read RH.
public struct ReadingTolerance: Sendable, Equatable {
    /// ± dry-bulb °F.
    public var dryBulbF: Int
    /// ± relative humidity %, for a directly-entered (Kestrel) reading.
    public var relativeHumidity: Int
    /// ± wet-bulb °F, for a slung reading (RH is re-derived through the
    /// psychrometric method at each perturbed wet bulb).
    public var wetBulbF: Int

    public init(dryBulbF: Int, relativeHumidity: Int, wetBulbF: Int) {
        self.dryBulbF = dryBulbF
        self.relativeHumidity = relativeHumidity
        self.wetBulbF = wetBulbF
    }

    /// The field default: ±2 °F, ±3% RH, ±2 °F wet bulb.
    public static let field = ReadingTolerance(dryBulbF: 2, relativeHumidity: 3, wetBulbF: 2)
}

/// The firmness of a Probability-of-Ignition value under plausible reading
/// error — how much the displayed PIG could move if the temperature/humidity
/// were off by the instrument tolerance.
///
/// This is a **live decision aid, not part of the frozen observation record**:
/// it is derived from the current screen inputs and never stored on a
/// ``WeatherObs``. The "firm" test is *band-firm* — the envelope is flagged only
/// when it crosses a fire-behavior band boundary (IRPG p.49), because what a crew
/// acts on is the band, not the exact percentage. A number that wiggles but keeps
/// its band reads as firm, keeping the signal rare and therefore trusted.
public struct Sensitivity: Sendable, Equatable {

    /// Whether the notable neighbouring reading is more or less hazardous than
    /// the displayed value.
    public enum Direction: Sendable, Equatable { case higher, lower }

    /// A plausible neighbouring reading and the PIG it produces. Its
    /// ``descriptor`` names only what differs from the displayed reading, so the
    /// caption stays short ("RH 6", "88°F", "88°F · RH 6").
    public struct Reading: Sendable, Equatable {
        /// Dry-bulb °F for this neighbouring reading.
        public let dryBulbF: Int
        /// Effective RH % for this neighbouring reading (derived, in sling mode).
        public let relativeHumidity: Int
        /// PIG % this reading produces for the envelope's shading condition.
        public let pig: Int
        /// True when this reading's dry bulb differs from the displayed reading.
        public let dryBulbShifted: Bool
        /// True when this reading's RH differs from the displayed reading.
        public let humidityShifted: Bool

        public init(dryBulbF: Int, relativeHumidity: Int, pig: Int,
                    dryBulbShifted: Bool, humidityShifted: Bool) {
            self.dryBulbF = dryBulbF
            self.relativeHumidity = relativeHumidity
            self.pig = pig
            self.dryBulbShifted = dryBulbShifted
            self.humidityShifted = humidityShifted
        }

        /// Fire-behavior band for this reading's PIG.
        public var band: FireBehavior { FireBehaviorInterpretation.interpretation(forPIG: pig) }

        /// The concise "what would be different" phrase for the caption. A notable
        /// reading always differs on at least one axis; the all-steady fallback is
        /// defensive only.
        public var descriptor: String {
            switch (dryBulbShifted, humidityShifted) {
            case (true, true): return "\(dryBulbF)°F · RH \(relativeHumidity)"
            case (true, false): return "\(dryBulbF)°F"
            default: return "RH \(relativeHumidity)"
            }
        }
    }

    /// The PIG envelope for one shading condition (unshaded or shaded).
    public struct Envelope: Sendable, Equatable {
        /// The displayed (unperturbed) PIG — always within `[pigLow, pigHigh]`.
        public let baseline: Int
        /// Lowest PIG across the plausible reading envelope.
        public let pigLow: Int
        /// Highest PIG across the plausible reading envelope.
        public let pigHigh: Int
        /// The reading worth surfacing when the envelope crosses a band — the
        /// more-hazardous side when one exists, else the softer side. `nil` when
        /// the whole envelope stays in one band (firm).
        public let notable: Reading?

        public init(baseline: Int, pigLow: Int, pigHigh: Int, notable: Reading?) {
            self.baseline = baseline
            self.pigLow = pigLow
            self.pigHigh = pigHigh
            self.notable = notable
        }

        /// Fire-behavior band of the displayed value.
        public var baselineBand: FireBehavior { FireBehaviorInterpretation.interpretation(forPIG: baseline) }

        /// True when the plausible envelope spans more than one fire-behavior
        /// band — the "not firm" signal that lights the amber marker.
        public var crossesBand: Bool { notable != nil }

        /// Which way the notable reading sits relative to the displayed value.
        public var direction: Direction? {
            guard let notable else { return nil }
            return notable.pig > baseline ? .higher : .lower
        }
    }

    public let unshaded: Envelope
    public let shaded: Envelope
    /// Human-readable envelope the analysis explored, e.g. `"±2°F · ±3% RH"`
    /// (direct) or `"±2°F · ±2°F wet bulb"` (sling) — for the expanded detail.
    public let toleranceSummary: String

    public init(unshaded: Envelope, shaded: Envelope, toleranceSummary: String) {
        self.unshaded = unshaded
        self.shaded = shaded
        self.toleranceSummary = toleranceSummary
    }

    /// The envelope for a shading condition.
    public func envelope(for shading: Shading) -> Envelope {
        shading == .shaded ? shaded : unshaded
    }
}

/// Computes ``Sensitivity`` by re-running the full IRPG chain across a small grid
/// of plausibly-off readings. Pure and dependency-free, so the whole thing is
/// golden-tested on Linux CI alongside the tables it perturbs.
public enum SensitivityAnalysis {

    /// One perturbed reading: a dry bulb and the effective RH it maps to.
    private struct Candidate { let dryBulbF: Int; let relativeHumidity: Int }

    /// Analyse the firmness of the estimate for the given screen state.
    ///
    /// Only the *measured* inputs (temperature and humidity) are perturbed —
    /// aspect, slope, elevation delta, month and time of day are categorical
    /// selections, not instrument reads with error, so they are held fixed. The
    /// baseline RH is derived exactly as the live screen derives it, so the
    /// envelope's `baseline` always equals the displayed PIG.
    ///
    /// - Parameters:
    ///   - dryBulbF: displayed dry-bulb °F.
    ///   - rhSource: whether RH is entered directly or slung from a wet bulb.
    ///   - relativeHumidity: displayed RH % (used when `rhSource == .direct`).
    ///   - wetBulbF: displayed wet-bulb °F (used when `rhSource == .wetBulb`).
    ///   - band: elevation band for the sling RH derivation.
    ///   - tolerance: the reading envelope to explore.
    public static func analyze(
        dryBulbF: Int,
        rhSource: RHSource,
        relativeHumidity: Int,
        wetBulbF: Int,
        band: ElevationBand,
        month: Int,
        timeOfDay: TimeOfDay,
        aspect: Aspect,
        slope: Slope,
        elevationDelta: ElevationDelta,
        tolerance: ReadingTolerance = .field
    ) -> Sensitivity {
        let baseRH: Int
        switch rhSource {
        case .direct:
            baseRH = min(max(relativeHumidity, 0), 100)
        case .wetBulb:
            baseRH = Psychrometrics.compute(dryBulbF: dryBulbF, wetBulbF: wetBulbF, band: band).relativeHumidity
        }

        let candidates = buildCandidates(
            dryBulbF: dryBulbF, rhSource: rhSource, relativeHumidity: relativeHumidity,
            wetBulbF: wetBulbF, band: band, tolerance: tolerance)

        func makeEnvelope(_ shading: Shading) -> Sensitivity.Envelope {
            envelope(shading: shading, baseDryBulbF: dryBulbF, baseRH: baseRH,
                     candidates: candidates, month: month, timeOfDay: timeOfDay,
                     aspect: aspect, slope: slope, elevationDelta: elevationDelta)
        }

        let summary: String
        switch rhSource {
        case .direct: summary = "±\(tolerance.dryBulbF)°F · ±\(tolerance.relativeHumidity)% RH"
        case .wetBulb: summary = "±\(tolerance.dryBulbF)°F · ±\(tolerance.wetBulbF)°F wet bulb"
        }

        return Sensitivity(unshaded: makeEnvelope(.unshaded), shaded: makeEnvelope(.shaded),
                           toleranceSummary: summary)
    }

    /// The 3×3 neighbourhood: dry bulb stepped by ±tolerance, and either RH
    /// (direct) or wet bulb (sling) stepped by ±tolerance. In sling mode the RH is
    /// re-derived at each perturbed dry/wet pair, so the nonlinear wet-bulb→RH
    /// amplification near saturation is captured honestly rather than approximated.
    private static func buildCandidates(
        dryBulbF: Int, rhSource: RHSource, relativeHumidity: Int, wetBulbF: Int,
        band: ElevationBand, tolerance: ReadingTolerance
    ) -> [Candidate] {
        let drySteps = [-tolerance.dryBulbF, 0, tolerance.dryBulbF]
        var out: [Candidate] = []
        switch rhSource {
        case .direct:
            let rhSteps = [-tolerance.relativeHumidity, 0, tolerance.relativeHumidity]
            for dt in drySteps {
                for dr in rhSteps {
                    out.append(Candidate(
                        dryBulbF: dryBulbF + dt,
                        relativeHumidity: min(max(relativeHumidity + dr, 0), 100)))
                }
            }
        case .wetBulb:
            let wetSteps = [-tolerance.wetBulbF, 0, tolerance.wetBulbF]
            for dt in drySteps {
                for dw in wetSteps {
                    let d = dryBulbF + dt
                    // Psychrometrics clamps wet ≤ dry internally.
                    let rh = Psychrometrics.compute(dryBulbF: d, wetBulbF: wetBulbF + dw, band: band).relativeHumidity
                    out.append(Candidate(dryBulbF: d, relativeHumidity: rh))
                }
            }
        }
        return out
    }

    private static func envelope(
        shading: Shading, baseDryBulbF: Int, baseRH: Int, candidates: [Candidate],
        month: Int, timeOfDay: TimeOfDay, aspect: Aspect, slope: Slope, elevationDelta: ElevationDelta
    ) -> Sensitivity.Envelope {

        func pig(dryBulbF: Int, relativeHumidity: Int) -> Int {
            IgnitionCalculator.estimate(IgnitionInput(
                dryBulbF: dryBulbF, relativeHumidity: relativeHumidity, month: month,
                timeOfDay: timeOfDay, aspect: aspect, slope: slope, elevationDelta: elevationDelta))
                .estimate(for: shading).probabilityOfIgnition
        }

        let baseline = pig(dryBulbF: baseDryBulbF, relativeHumidity: baseRH)
        let evaluated = candidates.map { (c: $0, pig: pig(dryBulbF: $0.dryBulbF, relativeHumidity: $0.relativeHumidity)) }
        let pigLow = evaluated.map(\.pig).min() ?? baseline
        let pigHigh = evaluated.map(\.pig).max() ?? baseline

        let baseBand = FireBehaviorInterpretation.interpretation(forPIG: baseline)
        func band(_ p: Int) -> FireBehavior { FireBehaviorInterpretation.interpretation(forPIG: p) }

        // Lead with the hazardous side when the envelope reaches a worse band;
        // otherwise surface a softer band if the low end crosses; else firm.
        let notable: Sensitivity.Reading?
        if band(pigHigh) != baseBand {
            notable = pickReading(target: pigHigh, evaluated: evaluated,
                                  baseDryBulbF: baseDryBulbF, baseRH: baseRH)
        } else if band(pigLow) != baseBand {
            notable = pickReading(target: pigLow, evaluated: evaluated,
                                  baseDryBulbF: baseDryBulbF, baseRH: baseRH)
        } else {
            notable = nil
        }

        return Sensitivity.Envelope(baseline: baseline, pigLow: pigLow, pigHigh: pigHigh, notable: notable)
    }

    /// The candidate hitting `target` PIG that tells the clearest "you're this
    /// close" story: the *fewest* shifted axes first (a one-variable miss reads
    /// clearer than a two-variable one), then the smallest perturbation. Ties
    /// break deterministically by the candidate grid order.
    private static func pickReading(
        target: Int, evaluated: [(c: Candidate, pig: Int)], baseDryBulbF: Int, baseRH: Int
    ) -> Sensitivity.Reading? {
        func axes(_ c: Candidate) -> Int {
            (c.dryBulbF != baseDryBulbF ? 1 : 0) + (c.relativeHumidity != baseRH ? 1 : 0)
        }
        func distance(_ c: Candidate) -> Int {
            abs(c.dryBulbF - baseDryBulbF) + abs(c.relativeHumidity - baseRH)
        }
        let hits = evaluated.filter { $0.pig == target }
        guard let best = hits.min(by: { a, b in
            let axesA = axes(a.c), axesB = axes(b.c)
            if axesA != axesB { return axesA < axesB }
            return distance(a.c) < distance(b.c)
        }) else { return nil }
        return Sensitivity.Reading(
            dryBulbF: best.c.dryBulbF,
            relativeHumidity: best.c.relativeHumidity,
            pig: best.pig,
            dryBulbShifted: best.c.dryBulbF != baseDryBulbF,
            humidityShifted: best.c.relativeHumidity != baseRH)
    }
}
