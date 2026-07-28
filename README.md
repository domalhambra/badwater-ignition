# Plateworks Ignition

A fast, offline iOS/macOS field calculator for **Probability of Ignition (PIG)**,
**Fine Fuel Moisture (FFM)**, and **relative humidity** — built directly on the
NWCG *Incident Response Pocket Guide* (IRPG, PMS 461) and belt-weather-kit tables.

Firefighters normally chain through Table A → the B/C/D correction tables → the
PIG table by hand, which is slow and error-prone. Plateworks Ignition walks that
exact chain, **shows its work at every step**, and computes PIG for both shaded
and unshaded fuels at once — while staying faithful to the printed guide, cell
for cell.

> Decision support only. **Not affiliated with or endorsed by the NWCG.** Always
> verify against your own IRPG and consult local experts.

## What it does

- **Ignition:** Temperature + RH + month + time-of-day + site factors (aspect,
  slope, elevation-vs-weather-site) → Reference Fuel Moisture → correction →
  Fine Fuel Moisture → **PIG (shaded and unshaded)**, plus the IRPG p.49
  plain-language fire-behavior interpretation. Handles the nighttime "+5" rule.
  RH is entered directly (off a Kestrel) or **derived from a wet-bulb
  temperature** (sling psychrometer / belt weather kit) right on the screen.
  Each PIG result also carries a **cell-edge marker**: because the IRPG tables
  are step functions, a reading a step or two from a cell edge can swing PIG a
  whole fire-behavior band — so a result that sits on such an edge is flagged
  (and tappable for the full envelope) while a firm one stays silent.
  Switching to wet bulb also reads out **dew point and wet-bulb depression**
  (NWCG psychrometric method, with Alaska elevation thresholds) beside the
  derived RH — the belt-weather-kit calculation happens where the reading is
  entered, not on a separate screen.

Temperatures are in **°F** throughout — the IRPG's native unit, and the standard
for U.S. wildland fire.

## Architecture

```
Package.swift                     PlateworksCore — pure, dependency-free, Linux-testable
Sources/PlateworksCore/
  Model/                          Aspect, Slope, Shading, TimeOfDay, MonthGroup, …
  Tables/                         Table A, B/C/D corrections, PIG table, p.49 interpretation
  Psychrometrics/                 Elevation bands + RH / dew point
  IgnitionCalculator.swift        the end-to-end chain
Tests/PlateworksCoreTests/          golden cells, banding boundaries, property tests, worked examples

App/PlateworksIgnition/             SwiftUI app (iOS + macOS)
  DesignSystem/                   Plateworks color/type tokens + components (VoiceOver-ready)
  Features/Ignition, Features/Humidity
  Assets.xcassets/Colors          light/dark palette (generated)
  PrivacyInfo.xcprivacy           privacy manifest (no data collected)
App/PlateworksIgnitionTests/        view-model unit tests (run in Xcode)
App/PlateworksIgnitionUITests/      black-box UI smoke tests (run in Xcode)
project.yml                       XcodeGen spec (app + test targets, test scheme)

web/                              PWA port (ignition.badwater.guide) — engine.js (logic twin
                                  of PlateworksCore) + app.js (UI twin of App/); static, offline-first
Sources/PlateworksVectors/          `swift run plateworks-vectors` — emits the conformance vectors
conformance/                      golden vectors + Node harness that hold web/ at parity in CI
docs/PARITY.md                    how iOS ⇄ web parity is enforced & auto-ported

DESIGN.md                         design system — finalize in Claude Design
docs/DATA_PROVENANCE.md           how every table value was transcribed & verified
docs/APP_STORE.md                 draft App Store listing copy
ATTRIBUTION.md                    NWCG public-domain sourcing + disclaimer
```

All correctness-critical logic lives in **`PlateworksCore`**, which has no UI and no
Apple-framework dependencies, so its full test suite runs on Linux CI.

## Web app & parity

The same tool ships as a static, offline-capable PWA at **ignition.badwater.guide**
(`web/`, deployed via Netlify). Its calculation engine (`web/engine.js`) is a
JavaScript twin of `PlateworksCore`, and parity is **enforced, not promised**:
golden vectors generated from the Swift core (`swift run plateworks-vectors`) are
replayed against the web engine in CI on every push — tables, ignition chains,
psychrometrics, radio scripts, and byte-exact IMET `.xlsx` output. When an
iOS-side change lands on `main` without its web counterpart, a GitHub Actions
agent (Claude Code) ports it and opens a draft parity PR gated by the same
checks. Design and contributor rules: [`docs/PARITY.md`](docs/PARITY.md).

## Build & test

**Core (any platform with a Swift toolchain):**
```sh
swift test
```

**App (macOS + Xcode 15+):**
```sh
brew install xcodegen        # once
xcodegen generate            # produces PlateworksIgnition.xcodeproj from project.yml
open PlateworksIgnition.xcodeproj
```
No XcodeGen? Create a new multiplatform SwiftUI App in Xcode, add the
`App/PlateworksIgnition` sources and the `Assets.xcassets`, and add `PlateworksCore`
as a local package dependency.

The color palette is generated:
```sh
python3 scripts/generate_color_assets.py
```

## Data fidelity

Every table value is a **cell-exact transcription** of the printed IRPG — not a
formula approximation — so the app agrees with the pocket guide line for line.
The transcription was independently re-read by multiple agents and reconciled
cell-by-cell, and is guarded by property tests (monotonicity, bounds, decade
values). See [`docs/DATA_PROVENANCE.md`](docs/DATA_PROVENANCE.md).

Relative humidity uses the sling-psychrometer relationship parameterized by the
band's station pressure. It was **validated cell-by-cell against the printed
PMS 437 tables** and matched exactly at every point checked (RH 3–94%, dry bulb
40–80 °F, dew points −21 to 66 °F, at 30 inHg and 27 inHg); those cells are
locked in as golden tests.
