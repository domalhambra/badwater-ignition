# CLAUDE.md — Badwater Ignition

Operator manual for Claude. Human entry point is `README.md`; project vision, status, and milestones are in `PROJECT_CHARTER.md`.

## What this project is

A fast, offline field calculator for wildland firefighters: **Probability of Ignition (PIG)**, **Fine Fuel Moisture (FFM)**, and **relative humidity**, computed cell-for-cell from the NWCG *Incident Response Pocket Guide* (IRPG, PMS 461) and belt-weather-kit tables. It ships twice from one repo:

- a **native SwiftUI app** (iOS/macOS) in `App/BadwaterIgnition/` — in development toward an App Store release, and
- a **static, offline-first web PWA** in `web/`, live at **ignition.badwater.guide**.

This is the only **safety-relevant** Badwater property. A wrong PIG on either platform is exactly the bug this repo exists to prevent, so fidelity to the printed guide is non-negotiable and correctness discipline (below) is not optional.

## Source-of-truth boundary

| Domain | Source of truth |
|---|---|
| All calculation logic | **`Sources/BadwaterCore/`** — pure Swift, no UI, no Apple-framework deps, Linux-testable. This is the truth. |
| Native UI | `App/BadwaterIgnition/` (SwiftUI, generated via XcodeGen from `project.yml`) |
| Web calculation | `web/engine.js` — a hand-written **JS twin of `BadwaterCore`**. Never the source; always the port. |
| Web UI | `web/app.js` (twin of `App/`) + `web/index.html` |
| IRPG table values | cell-exact transcriptions, provenance-documented in `docs/DATA_PROVENANCE.md`. Not formula approximations. |
| Conformance vectors | generated from `BadwaterCore` via `swift run badwater-vectors` → `conformance/vectors.json` |

**Rule:** change `BadwaterCore` first, then port to `web/engine.js`. The web side never leads.

## Parity discipline (the core rule)

The two implementations must never drift. Parity is **enforced by the build, not by diligence**:

- `node conformance/check-web.js` replays the Swift-generated golden vectors against `web/engine.js` — tables, ignition chains, psychrometrics, radio scripts, and **byte-exact** IMET `.xlsx`. CI fails on any disagreement.
- When an iOS-side change lands on `main` without its web counterpart, a **GitHub Actions agent (`.github/workflows/web-parity-agent.yml`) ports it and opens a draft parity PR** gated by the same checks.
- Full design & contributor rules: `docs/PARITY.md`.

If you touch calculation on either side, regenerate vectors and run the conformance check before claiming done.

## Build & test

```sh
swift test                    # BadwaterCore suite — runs on any Swift toolchain (incl. Linux CI)
node conformance/check-web.js # web ⇄ core parity gate
```

Native app (macOS + Xcode):
```sh
brew install xcodegen         # once
xcodegen generate             # BadwaterIgnition.xcodeproj from project.yml
```
The color palette is generated: `python3 scripts/generate_color_assets.py`.

The `web/` app has **no build step** and no dependencies — it's static files served as-is.

## Deploy & hosting

- **Continuous deploy:** the web app is a **git-connected Netlify site** (`badwater-ignition`). Pushing to `main` auto-deploys `web/` (base directory `web/`, no build command). There is no manual deploy step.
- **When you change any cached web asset, bump `CACHE` in `web/sw.js`** (currently `badwater-ignition-v4` → `-v5`, …) or field devices keep serving the old app offline.
- **Domain:** `ignition.badwater.guide` (canonical). The former host `obs.badwater.guide` is kept as a Netlify domain alias and **301-redirects** (rule in `web/netlify.toml`); its Cloudflare CNAME stays for the redirect to fire. Both are proxied CNAMEs → `badwater-ignition.netlify.app` in the `badwater.guide` Cloudflare zone.
- GitHub: `domalhambra/badwater-ignition`.

## Guardrails

- **"Obs" is a feature, not the brand.** The app's three tabs are **Humidity · Ignition · Obs** (Obs = the weather-observations tab). The product is **"Badwater Ignition"** (singular, matching the native app). Never rename the "Obs" tab/feature vocabulary to "Ignition," and never re-plural the brand.
- **Safety-relevant, decision-support only.** Not affiliated with or endorsed by the NWCG. Keep the disclaimer intact; keep every table value provenance-documented.
- **Offline-first & private.** All compute runs on-device / in-page. No outbound requests, no data collection (see `PrivacyInfo.xcprivacy`, the CSP in `netlify.toml`). Don't add network dependencies.
- Follows the workspace **Project Conventions** in `../CLAUDE.md` (plan before multi-step work; verification is the last step; reciprocal cross-referencing). Session work is logged to the PKM `SESSION_LOG.md` via the session-log skill, not a repo-local log.

## Map of the repo

| Path | What |
|---|---|
| `Sources/BadwaterCore/` | pure calculation core (source of truth) |
| `Sources/BadwaterVectors/` | `swift run badwater-vectors` — emits conformance vectors |
| `App/BadwaterIgnition/` | SwiftUI app (iOS/macOS) + its test targets |
| `web/` | offline PWA (engine.js, app.js, index.html, sw.js, manifest, netlify.toml) |
| `conformance/` | golden vectors + Node parity harness |
| `PROJECT_CHARTER.md` | vision, status, milestones |
| `DESIGN.md` | design system |
| `docs/PARITY.md`, `docs/DATA_PROVENANCE.md`, `docs/APP_STORE.md` | parity machinery, table provenance, store listing draft |
| `ATTRIBUTION.md` | NWCG public-domain sourcing + disclaimer |
