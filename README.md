# Badwater Ignition

A fast, offline iOS/macOS field calculator for **Probability of Ignition (PIG)**,
**Fine Fuel Moisture (FFM)**, and **relative humidity** — built directly on the
NWCG *Incident Response Pocket Guide* (IRPG, PMS 461) and belt-weather-kit tables.

Firefighters normally chain through Table A → the B/C/D correction tables → the
PIG table by hand, which is slow and error-prone. Badwater Ignition walks that
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
- **Humidity:** Dry-bulb + wet-bulb + elevation band → **relative humidity and
  dew point** (NWCG psychrometric method, with Alaska thresholds). One tap sends
  the result into the Ignition calculator.

## Architecture

```
Package.swift                     BadwaterCore — pure, dependency-free, Linux-testable
Sources/BadwaterCore/
  Model/                          Aspect, Slope, Shading, TimeOfDay, MonthGroup, …
  Tables/                         Table A, B/C/D corrections, PIG table, p.49 interpretation
  Psychrometrics/                 Elevation bands + RH / dew point
  IgnitionCalculator.swift        the end-to-end chain
Tests/BadwaterCoreTests/          golden cells, banding boundaries, property tests, worked examples

App/BadwaterIgnition/             SwiftUI app (iOS + macOS)
  DesignSystem/                   Badwater color/type tokens + components
  Features/Ignition, Features/Humidity
  Assets.xcassets/Colors          light/dark palette (generated)
project.yml                       XcodeGen spec (app target)
DESIGN.md                         design system — finalize in Claude Design
docs/DATA_PROVENANCE.md           how every table value was transcribed & verified
```

All correctness-critical logic lives in **`BadwaterCore`**, which has no UI and no
Apple-framework dependencies, so its full test suite runs on Linux CI.

## Build & test

**Core (any platform with a Swift toolchain):**
```sh
swift test
```

**App (macOS + Xcode 15+):**
```sh
brew install xcodegen        # once
xcodegen generate            # produces BadwaterIgnition.xcodeproj from project.yml
open BadwaterIgnition.xcodeproj
```
No XcodeGen? Create a new multiplatform SwiftUI App in Xcode, add the
`App/BadwaterIgnition` sources and the `Assets.xcassets`, and add `BadwaterCore`
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

Relative humidity uses the WMO sling-psychrometer relationship parameterized by
the band's station pressure; it reproduces the printed PMS 437 tables to within
rounding and is pinned by tests.
