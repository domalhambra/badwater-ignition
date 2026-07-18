# Conformance vectors — iOS ⇄ web parity gate

`vectors.json` is generated from **`Sources/BadwaterCore`** (the source of
truth) and replayed against **`web/engine.js`** (the JavaScript port that
powers obs.badwater.guide). CI fails whenever the two implementations disagree,
so parity is enforced by the build, not by diligence. Full design:
[`docs/PARITY.md`](../docs/PARITY.md).

## Commands

```sh
# regenerate after changing BadwaterCore (CI fails if you forget)
swift run badwater-vectors --out conformance/vectors.json

# verify vectors.json still matches the core (what CI runs)
swift run badwater-vectors --check conformance/vectors.json

# verify the web engine against the vectors (what CI runs; no npm deps)
node conformance/check-web.js
```

## What is covered

| Section | Pins |
|---|---|
| `tables` | Full IRPG grids (Table A, B/C/D corrections, PIG unshaded/shaded) rebuilt through the public lookup API |
| `rfmCases` / `corrCases` / `pigCases` | Band/row/column indexing at every boundary, including clamps |
| `behaviorTable` / `behaviorCases` / `caution` | Fire-behavior titles, ranges, interpretation text, band mapping |
| `monthGroupCases` / `timeBandCases` | Month → table B/C/D; clock → time band (night boundaries) |
| `psychroCases` | RH / dew point / depression across the belt-weather-kit range, all pressure bands |
| `elevationBandCases` | CONUS + Alaska band thresholds, below-sea-level clamp |
| `chainCases` | End-to-end estimates (ref FM → correction → FFM → PIG → behavior), day + night |
| `windCases` | Spot / spoken / IMET renderings, calm & gust semantics |
| `radioCases` | Complete broadcast scripts: deltas, site re-announcement rules, wind sentence |
| `crc32Cases` | Zip checksum |
| `xlsxCases` | **Byte-exact** IMET `.xlsx` workbooks (multi-day, duplicate tabs, empty book) |
| `sensitivityCases` | Emitted but **skipped** by the harness — known divergence, see PARITY.md |

Array-encoded case formats are documented in `vectors.json` → `meta`.

Date-derived expectations (xlsx sheet names/titles) assume `TZ=UTC`; the
harness pins it and CI sets it explicitly.
