# Project Charter — Badwater Ignition

_Chartered 2026-07-18. This is a retroactive charter: the project was already mature (native app + web port + parity CI) when it was formally filed into the workspace._

## What it is

A fast, offline **iOS/macOS + web** field calculator for **Probability of Ignition (PIG)**, **Fine Fuel Moisture (FFM)**, and **relative humidity**, built cell-for-cell on the NWCG *Incident Response Pocket Guide* (IRPG, PMS 461) and belt-weather-kit tables. It walks the Table A → B/C/D correction → PIG chain that firefighters otherwise do by hand, shows its work at every step, and flags results sitting on a table cell edge (where a step can swing a whole fire-behavior band).

Decision-support only. Not affiliated with or endorsed by the NWCG.

## Vision / done state

**A public App Store release** (iOS/macOS) for the wider wildland fire community, with the web PWA as the free, install-anywhere companion. "Done" is: the native app shipped on the App Store, the web app live and at parity, and the IRPG transcription fully provenance-documented.

## Current status (2026-07-18)

- **Web PWA — LIVE** at [ignition.badwater.guide](https://ignition.badwater.guide) (Netlify, git-connected continuous deploy). Rebranded from "Badwater Obs" → "Badwater Ignition" and moved from `obs.` → `ignition.` today; old host 301-redirects.
- **Native iOS/macOS app — in development.** Source-complete with unit + UI test targets; not yet distributed (no TestFlight/App Store build yet).
- **Parity — enforced.** Conformance vectors from the Swift core replay against the web engine in CI on every push.

## Location & filing

- **Repo folder:** `Projects/Badwater OS/Badwater Ignitions/`
- **GitHub:** `domalhambra/badwater-calculator`
- **Netlify site:** `badwater-ignition` → `badwater-ignition.netlify.app`
- **DNS:** Cloudflare, `badwater.guide` zone — proxied CNAME `ignition` (+ `obs` alias for the 301)
- **Workspace filing:** listed in `Badwater OS/CLAUDE.md` Projects table + Fallback route (fire-tool / IRPG questions).
- **JD context:** subject-matter home is *20-29 Work Projects* (federal wildland fire), but as a full-repo project it lives under `Badwater OS/` alongside PKM / HD / Garden.

## Architecture (see `README.md` + `DESIGN.md` for detail)

- `Sources/BadwaterCore/` — pure, dependency-free, Linux-testable calculation core (the source of truth).
- `App/BadwaterIgnition/` — SwiftUI app (iOS + macOS), generated via XcodeGen (`project.yml`).
- `web/` — static, offline-first PWA: `engine.js` (logic twin of `BadwaterCore`) + `app.js` (UI twin of `App/`).
- `Sources/BadwaterVectors/` + `conformance/` — golden vectors + Node harness that hold the two ports at parity.

## Design & reference docs

| Doc | Purpose |
|---|---|
| `DESIGN.md` | Design system (finalize in Claude Design) |
| `docs/PARITY.md` | How iOS ⇄ web parity is enforced & auto-ported |
| `docs/DATA_PROVENANCE.md` | How every IRPG table value was transcribed & verified |
| `docs/APP_STORE.md` | Draft App Store listing copy |
| `ATTRIBUTION.md` | NWCG public-domain sourcing + disclaimer |

## Logging strategy

Session work is logged to the workspace `SESSION_LOG.md` (`Badwater PKM/wiki/00-meta/`) via the session-log skill — not a repo-local log. Deploys/launches get `Status: Shipped` + `#shipped` and a shipped-index pointer.

## Verification gates

- `swift test` — `BadwaterCore` suite (golden cells, banding boundaries, property tests, worked examples) runs on Linux CI.
- **Conformance CI** — `node conformance/check-web.js` replays Swift-generated vectors against `web/engine.js`: tables, ignition chains, psychrometrics, radio scripts, and byte-exact IMET `.xlsx`. CI fails on any disagreement.
- **Web-parity agent** — when an iOS change lands on `main` without its web counterpart, a GitHub Actions agent ports it and opens a draft parity PR gated by the same checks.
- App-side: Xcode unit + UI test targets.
- Bump `sw.js` `CACHE` on every web change so field devices refetch.

## Tooling

Swift / SwiftUI · XcodeGen · vanilla-JS PWA (no build step, no deps) · Netlify (continuous deploy) · Cloudflare DNS · GitHub Actions (parity CI + agent).

## Milestones

- [x] **Web PWA live** at `ignition.badwater.guide` — 2026-07-18
- [x] Brand unified to "Badwater Ignition" across native + web
- [ ] Finalize `DESIGN.md` design system pass
- [ ] Native app → **TestFlight beta** (first external testers)
- [ ] Finalize `docs/APP_STORE.md` listing + assets (screenshots, privacy)
- [ ] **App Store release** (iOS/macOS)
- [ ] Ongoing: keep web ⇄ iOS parity green through release

## Guardrails / principles

- **Safety-relevant.** Decision-support only; cell-exact fidelity to the printed IRPG is non-negotiable, and every table value stays provenance-documented.
- **Offline-first, private.** All compute runs on-device / in-page; no data collection, no outbound requests.
- **Parity is enforced, not promised.** The two ports never diverge silently.
