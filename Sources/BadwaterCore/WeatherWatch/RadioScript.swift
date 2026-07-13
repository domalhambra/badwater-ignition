import Foundation

/// Renders the spoken radio broadcast for a logged observation, in the standard
/// crew script format:
///
/// > "Diamond Mountain, stand by for your 0900 Weather observations. Taken near
/// > the 659 road at an elevation of 10,300 feet, on a Western aspect. Dry Bulb
/// > 60 degrees, up 5, RH 25%, down 3. Winds are 1-3 miles per hour from the West,
/// > Probability of Ignition Unshaded is 50%, Shaded is 30%. I repeat, Dry Bulb
/// > 60 degrees, up 5, RH 25%, down 3. How copy?"
///
/// Deltas ("up 5", "down 3") compare against the previous broadcast obs; the
/// first obs of a shift speaks no deltas. The location sentence (site,
/// elevation, slope, aspect) is spoken on the first broadcast and whenever the
/// site actually changed — the spoken-location text, elevation, aspect, or
/// slope differs from the previous obs. Two explicit operator overrides exist:
/// `forceLocation` re-announces an unchanged site, and `suppressLocation` is
/// the operator's "location unchanged" assertion — it always wins, so a typo
/// fix in the location text doesn't force a spurious re-announcement.
public enum RadioScript {

    public static func render(
        addressee: String,
        timeLabel: String,
        spokenLocation: String?,
        current: WeatherObs,
        previous: WeatherObs?,
        forceLocation: Bool = false,
        suppressLocation: Bool = false
    ) -> String {
        var sentences: [String?] = []

        // Opening. The dictated capitalization is "Weather observations" —
        // capital W, lowercase o. It's byte-exact from the field script; leave it.
        let name = addressee.trimmingCharacters(in: .whitespaces)
        sentences.append(name.isEmpty
            ? "Stand by for your \(timeLabel) Weather observations."
            : "\(name), stand by for your \(timeLabel) Weather observations.")

        if !suppressLocation,
           shouldSpeakLocation(current: current, previous: previous,
                               spokenLocation: spokenLocation, forceLocation: forceLocation) {
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

    /// The site is re-announced on the first broadcast, whenever the spoken
    /// location text / elevation / aspect / slope changed, or on demand. GPS
    /// micro-movement deliberately doesn't count. A `nil` previous spoken
    /// location (pre-feature record) counts as changed, so the first broadcast
    /// after an upgrade re-announces rather than silently omitting a move.
    static func shouldSpeakLocation(
        current: WeatherObs, previous: WeatherObs?,
        spokenLocation: String?, forceLocation: Bool
    ) -> Bool {
        guard let previous else { return true }
        if forceLocation { return true }
        return previous.elevationFeet != current.elevationFeet
            || previous.estimate.input.aspect != current.estimate.input.aspect
            || previous.estimate.input.slope != current.estimate.input.slope
            || normalized(previous.spokenLocation) != normalized(spokenLocation)
    }

    /// Trimmed, empty-collapsed-to-nil form used for the location-text diff, so
    /// stray whitespace never causes a phantom re-announcement. Newlines count
    /// as whitespace too — pasted text often carries a trailing `\n`, which must
    /// neither re-trigger the announcement nor end up inside the spoken sentence.
    static func normalized(_ location: String?) -> String? {
        guard let t = location?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// `"Taken {loc} at an elevation of {10,300} feet, on a Western aspect."` —
    /// the location phrase carries its own preposition (e.g. "near the 659 road",
    /// "at the lookout") and is spoken verbatim after "Taken"; nil parts drop out
    /// gracefully. The app never injects a preposition, so the operator phrases
    /// the location exactly as they want it read on the net. Steep terrain
    /// (31%+) is called out — "on a steep Western aspect" — gentle slope stays
    /// silent, matching the dictated field script.
    static func locationSentence(spokenLocation: String?, obs: WeatherObs) -> String {
        var s = "Taken"
        var hasDetail = false
        if let loc = normalized(spokenLocation) {
            s += " \(loc)"
            hasDetail = true
        }
        if let feet = obs.elevationFeet {
            s += " at an elevation of \(grouped(feet)) feet"
            hasDetail = true
        }
        let aspect = obs.estimate.input.aspect
        let steep = obs.estimate.input.slope == .steep
        // "steep" takes over the article slot: "a steep Eastern aspect", not "an".
        let art = steep ? "a" : article(for: aspect)
        let descriptor = steep ? "steep \(adjective(for: aspect))" : adjective(for: aspect)
        let tail = "\(art) \(descriptor) aspect."
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
