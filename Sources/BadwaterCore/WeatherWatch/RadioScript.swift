import Foundation

/// Renders the spoken radio broadcast for a logged observation, in the standard
/// crew script format:
///
/// > "Diamond Mountain, stand by for your 0900 Weather observations. Taken near
/// > the 659 road at an elevation of 10,300 feet, on a Western aspect. Dry Bulb
/// > 60 degrees, up 5, RH 25%, down 3. Winds are 1-3 miles from the West,
/// > Probability of Ignition Unshaded is 50%, Shaded is 30%. I repeat, Dry Bulb
/// > 60 degrees, up 5, RH 25%, down 3. How copy?"
///
/// Deltas ("up 5", "down 3") compare against the previous broadcast obs; the
/// first obs of a shift speaks no deltas. The location sentence (site,
/// elevation, aspect) is spoken only on the first broadcast, when elevation or
/// aspect changed since the previous obs, or when `forceLocation` is set (site
/// renamed mid-shift, operator change, etc.).
public enum RadioScript {

    public static func render(
        addressee: String,
        timeLabel: String,
        spokenLocation: String?,
        current: WeatherObs,
        previous: WeatherObs?,
        forceLocation: Bool = false
    ) -> String {
        var sentences: [String?] = []

        // Opening. The dictated capitalization is "Weather observations" —
        // capital W, lowercase o. It's byte-exact from the field script; leave it.
        let name = addressee.trimmingCharacters(in: .whitespaces)
        sentences.append(name.isEmpty
            ? "Stand by for your \(timeLabel) Weather observations."
            : "\(name), stand by for your \(timeLabel) Weather observations.")

        if shouldSpeakLocation(current: current, previous: previous, forceLocation: forceLocation) {
            sentences.append(locationSentence(spokenLocation: spokenLocation, obs: current))
        }

        // Body clause (unterminated) is reused verbatim by the "I repeat" block.
        let body = bodyClause(current: current, previous: previous)
        sentences.append("\(body).")

        let pig = "Probability of Ignition Unshaded is \(current.estimate.unshaded.probabilityOfIgnition)%, "
            + "Shaded is \(current.estimate.shaded.probabilityOfIgnition)%."
        if let wind = current.wind {
            sentences.append("Winds are \(wind.spokenPhrase), \(pig)")
        } else {
            sentences.append(pig)
        }

        sentences.append("I repeat, \(body).")
        sentences.append("How copy?")
        return sentences.compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Sentence builders

    /// The site is re-announced on the first broadcast, on any elevation or
    /// aspect change, or on demand. GPS micro-movement deliberately doesn't count.
    static func shouldSpeakLocation(current: WeatherObs, previous: WeatherObs?, forceLocation: Bool) -> Bool {
        guard let previous else { return true }
        if forceLocation { return true }
        return previous.elevationFeet != current.elevationFeet
            || previous.estimate.input.aspect != current.estimate.input.aspect
    }

    /// `"Taken near {loc} at an elevation of {10,300} feet, on a Western aspect."`
    /// The location phrase is spoken verbatim; nil parts drop out gracefully.
    static func locationSentence(spokenLocation: String?, obs: WeatherObs) -> String {
        var s = "Taken"
        var hasDetail = false
        if let loc = spokenLocation?.trimmingCharacters(in: .whitespaces), !loc.isEmpty {
            s += " near \(loc)"
            hasDetail = true
        }
        if let feet = obs.elevationFeet {
            s += " at an elevation of \(grouped(feet)) feet"
            hasDetail = true
        }
        let aspect = obs.estimate.input.aspect
        let tail = "\(article(for: aspect)) \(adjective(for: aspect)) aspect."
        s += hasDetail ? ", on \(tail)" : " on \(tail)"
        return s
    }

    /// `"Dry Bulb 60 degrees, up 5, RH 25%, down 3"` — deltas vs. the previous
    /// obs; no deltas on the first obs of a shift.
    static func bodyClause(current: WeatherObs, previous: WeatherObs?) -> String {
        let t = current.estimate.input.dryBulbF
        let rh = current.estimate.input.relativeHumidity
        let tDelta = previous.map { delta(t - $0.estimate.input.dryBulbF) } ?? ""
        let rhDelta = previous.map { delta(rh - $0.estimate.input.relativeHumidity) } ?? ""
        return "Dry Bulb \(t) degrees\(tDelta), RH \(rh)%\(rhDelta)"
    }

    static func delta(_ d: Int) -> String {
        if d == 0 { return ", steady" }
        return d > 0 ? ", up \(d)" : ", down \(-d)"
    }

    // MARK: - Spoken vocabulary

    static func adjective(for aspect: Aspect) -> String {
        switch aspect {
        case .north: return "Northern"
        case .east: return "Eastern"
        case .south: return "Southern"
        case .west: return "Western"
        }
    }

    static func article(for aspect: Aspect) -> String {
        aspect == .east ? "an" : "a"
    }

    /// Locale-invariant thousands grouping: 10300 → `"10,300"`. Hand-rolled
    /// (never NumberFormatter) so Linux CI and comma-decimal devices agree.
    static func grouped(_ value: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let digits = Array(String(value.magnitude))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return sign + out
    }
}
