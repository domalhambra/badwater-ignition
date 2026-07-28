import Foundation

/// Header for a spot-request observations block.
public struct SpotObsHeader: Equatable, Sendable {
    public let site: String
    public let latLong: String?
    public let elevationFeet: Int?
    public let aspect: String?
    public let dateLabel: String
    public init(site: String, latLong: String? = nil, elevationFeet: Int? = nil, aspect: String? = nil, dateLabel: String) {
        self.site = site; self.latLong = latLong; self.elevationFeet = elevationFeet
        self.aspect = aspect; self.dateLabel = dateLabel
    }
}

/// One observation line for a spot-request block. Strings are pre-rendered by the
/// app so this stays decoupled from ``Wind``/``GeoPoint``.
public struct SpotObsLine: Equatable, Sendable {
    public let timeHHmm: String
    public let dryBulbF: Int
    public let wetBulbF: Int?
    public let relativeHumidity: Int
    public let dewPointF: Int?
    public let windText: String?     // Wind.spotString
    public let poiUnshaded: Int?
    public let poiShaded: Int?
    public let monthDay: String      // "7/6" — drives a divider when the shift crosses local midnight
    public init(timeHHmm: String, dryBulbF: Int, wetBulbF: Int?, relativeHumidity: Int, dewPointF: Int?, windText: String?, poiUnshaded: Int?, poiShaded: Int?, monthDay: String) {
        self.timeHHmm = timeHHmm; self.dryBulbF = dryBulbF; self.wetBulbF = wetBulbF
        self.relativeHumidity = relativeHumidity; self.dewPointF = dewPointF; self.windText = windText
        self.poiUnshaded = poiUnshaded; self.poiShaded = poiShaded; self.monthDay = monthDay
    }
}

/// Renders a shift's observations as an ASCII plain-text block to paste into the
/// NWS Spot Weather Forecast Request comments box (which invites more than the
/// four grid rows) or to hand an IMET directly. Neutral: the app-derived PIG is
/// optional, labeled, and footnoted "not observed, not a forecast".
public enum SpotObservationsRenderer {

    public static func plainText(header: SpotObsHeader, rows: [SpotObsLine], includePoI: Bool = true) -> String {
        var lines: [String] = []
        lines.append("On-site weather observations - " + header.site)
        var meta = ["Date " + header.dateLabel]
        if let l = header.latLong { meta.append("Loc " + l) }
        if let e = header.elevationFeet { meta.append("Elev \(e) ft") }
        if let a = header.aspect { meta.append("Aspect " + a) }
        lines.append(meta.joined(separator: "  "))
        lines.append("Units temp/wet/dew F, RH %, wind mph (from), elev ft. Times local 24h.")

        if rows.isEmpty {
            lines.append("")
            lines.append("No observations logged this shift.")
            return finish(lines)
        }

        lines.append("")
        let sep = "  "
        // Column header + rule (Wind is last so the numeric columns always align)
        var head = [padR("Time", 4), padL("Temp", 4), padL("Wet", 3), padL("RH", 3), padL("Dew", 3)]
        var rule = [dashes(4), dashes(4), dashes(3), dashes(3), dashes(3)]
        if includePoI { head.append(padL("PoI(U/S)", 8)); rule.append(dashes(8)) }
        head.append("Wind"); rule.append(dashes(12))
        lines.append(head.joined(separator: sep))
        lines.append(rule.joined(separator: sep))

        var currentMD = rows[0].monthDay
        for (i, r) in rows.enumerated() {
            if i > 0 && r.monthDay != currentMD {
                lines.append("-- \(r.monthDay) --")
                currentMD = r.monthDay
            }
            var cells = [
                padR(r.timeHHmm, 4), padL("\(r.dryBulbF)", 4),
                padL(r.wetBulbF.map { "\($0)" } ?? "--", 3),
                padL("\(r.relativeHumidity)", 3),
                padL(r.dewPointF.map { "\($0)" } ?? "--", 3),
            ]
            if includePoI {
                let poi = (r.poiUnshaded.map(String.init).flatMap { u in r.poiShaded.map { "\(u)/\($0)" } }) ?? "--"
                cells.append(padL(poi, 8))
            }
            cells.append(r.windText ?? "--")
            lines.append(cells.joined(separator: sep))
        }

        lines.append("")
        if includePoI { lines.append("PoI = IRPG Probability of Ignition, app-computed (not observed, not a forecast).") }
        lines.append("Wet/Dew shown only when slung from a wet bulb; RH otherwise from a meter.")
        lines.append("Logged with Plateworks Ignition - decision-support only, not affiliated with NWS/NWCG.")
        return finish(lines)
    }

    private static func finish(_ lines: [String]) -> String {
        lines.map(rstrip).joined(separator: "\n") + "\n"
    }
    private static func dashes(_ n: Int) -> String { String(repeating: "-", count: n) }
    private static func padL(_ s: String, _ w: Int) -> String { s.count >= w ? s : String(repeating: " ", count: w - s.count) + s }
    private static func padR(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }
    private static func rstrip(_ s: String) -> String {
        var t = s
        while t.hasSuffix(" ") { t.removeLast() }
        return t
    }
}
