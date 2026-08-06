# iOS ⇄ Web parity: how it stays true

Plateworks Ignition ships twice: the SwiftUI app (iOS/macOS, built on
`Sources/PlateworksCore`) and the hand-written vanilla-JS PWA in `web/`
(ignition.plateworks.org). Two implementations of one safety-relevant spec is a
standing invitation to drift — a wrong PIG on one platform is exactly the bug
this repo exists to prevent. This document describes the machinery that makes
parity **enforced by the build and automated by an agent**, not maintained by
diligence.

There are three layers. Each works alone; together they close the loop.

```
Sources/PlateworksCore  ──(swift run plateworks-vectors)──►  conformance/vectors.json
        │                                                        │
        │  CI: vectors must regenerate byte-identically          │  CI: web/engine.js must
        │  ("vectors are fresh" — core-tests job)                │  replay every vector
        ▼                                                        ▼  (web-conformance job)
   iOS app (App/)                                          web/engine.js + app.js
        │                                                        ▲
        └── push to main touching Sources/ or App/ ──────────────┘
            without touching web/  ──►  Web parity agent (Claude Code)
                                        ports the change, gates on the
                                        harness, opens a draft parity PR
```

## Layer 1 — the web engine is a testable twin

`web/index.html` used to hold the entire app inline. It is now split:

- **`web/engine.js`** — every calculation and text/binary output: IRPG tables,
  the ignition chain, psychrometrics, wind renderings, the radio script, CRC32,
  the zip writer, and the IMET `.xlsx` builder. No DOM, no storage, no clock —
  so Node can `require()` it directly. This file mirrors `Sources/PlateworksCore`.
- **`web/app.js`** — state, rendering, and event wiring. Mirrors `App/`.

Classic scripts share the global lexical scope, so the split costs no build
step, no bundler, no dependencies — the deploy story (static files on Netlify)
is unchanged. The seam also gives the parity agent an unambiguous porting rule:
core changes land in `engine.js`, feature/UI changes land in `app.js`.

## Layer 2 — golden vectors make divergence unmergeable

`swift run plateworks-vectors --out conformance/vectors.json` derives ~1,200
checks **through PlateworksCore's public API** and writes them as deterministic,
hand-formatted JSON (one case per line; reviewable diffs; no timestamps).
Coverage spans the full grids, every banding boundary and clamp, end-to-end
ignition chains, psychrometrics across all pressure bands, complete radio
scripts, and **byte-exact IMET `.xlsx` workbooks** (possible because the zip
writer uses a fixed DOS timestamp on both sides). See
[`conformance/README.md`](../conformance/README.md) for the section map.

Two CI jobs (`.github/workflows/ci.yml`) hold the line:

1. **Vectors are fresh** (`core-tests`, Swift container):
   `swift run plateworks-vectors --check conformance/vectors.json` fails if the
   core changed without regenerating the committed vectors.
2. **Web parity** (`web-conformance`, plain Node, `TZ=UTC`):
   `node conformance/check-web.js` fails if `web/engine.js` disagrees with the
   vectors on any check.

Combined effect: a core change cannot merge green without updated vectors, and
updated vectors cannot merge green without the web engine matching them. The
two implementations can only move together.

> Proof it works: on its **first ever run** the harness caught two real,
> field-facing web bugs that had shipped — measured winds were silently
> dropped from the radio broadcast unless gusting (`wind.speed` vs
> `wind.high`), and any pre-0800 clock time landed in the 1000–1159 correction
> column instead of the IRPG night "+5" rule. Both are fixed and now pinned by
> `radioCases` and `timeBandCases`.

## Layer 3 — the parity agent automates the port itself

`.github/workflows/web-parity-agent.yml` watches pushes to `main` that touch
`Sources/**` or `App/**` but not `web/`. It runs Claude Code
(`anthropics/claude-code-action@v1`) with a porting brief: inspect the pushed
diff, port it to `engine.js`/`app.js`/`index.html`, **bump the service-worker
cache version**, iterate until the conformance harness is green, and open a
**draft PR** titled `web parity: …` — or explicitly conclude that nothing was
web-visible. CI then re-verifies the same harness on the PR, so the agent's
work is gated by the same deterministic checks as a human's.

The division of labor is the point: the agent makes the port cheap; the
vectors make it trustworthy. Neither alone is sufficient for a tool crews use
on a fireline.

**Setup (one-time):** the workflow authenticates with a Claude Pro/Max
subscription by default — no API billing required. On any machine with the
Claude Code CLI installed and logged into your subscription, run:

```sh
claude setup-token
```

This prints a long-lived OAuth token. In the repo on GitHub, go to
**Settings → Secrets and variables → Actions → New repository secret**, name
it `CLAUDE_CODE_OAUTH_TOKEN`, and paste the token as the value. That's the
whole setup — the workflow (`.github/workflows/web-parity-agent.yml`) already
reads that secret.

Prefer to bill through the API instead? Create a key at
[console.anthropic.com](https://console.anthropic.com), add it as an
`ANTHROPIC_API_KEY` repository secret the same way, then in the workflow swap
the `claude_code_oauth_token: …` line for `anthropic_api_key: ${{
secrets.ANTHROPIC_API_KEY }}`.

Without either secret the workflow fails visibly — parity is then still
*detected* by Layer 2 (CI stays red), just not auto-ported.

**Loop safety:** parity PRs touch only `web/`, which the trigger ignores, so
the agent never triggers itself. Concurrent pushes serialize via a concurrency
group. `workflow_dispatch` allows manual/backfill runs.

## Working in this repo

- **Changing `Sources/PlateworksCore`** → regenerate vectors in the same PR:
  `swift run plateworks-vectors --out conformance/vectors.json`. CI fails
  otherwise. If your PR doesn't also port the web side, the agent will follow
  up after merge; `main`'s web-conformance job stays red until the parity PR
  merges (an honest signal, not a nuisance).
- **Changing `web/engine.js`** → `node conformance/check-web.js` must stay
  green. Never edit `conformance/vectors.json` by hand — it is generated, and
  the Swift side is the source of truth.
- **Changing anything under `web/`** → bump `CACHE` in `web/sw.js`. The PWA
  is offline-first; without the bump, field devices keep the old app.
- **Never** weaken the harness or the vectors to get to green.

Want parity strictly atomic instead of agent-followed? Mark the
`web-conformance` check **required** in branch protection — then an iOS logic
change simply cannot merge without its web port in the same PR. The agent
workflow still helps by pushing the port commit onto your PR branch on demand
(`workflow_dispatch`).

## Known divergences (deliberate, tracked)

| Area | iOS / core | web today | Status |
|---|---|---|---|
| Sensitivity ("near edge" hint) | `SensitivityAnalysis`: 3×3 perturbation grid, ±2 °F wet bulb, notable-reading selection | `app.js edge()`: 4-corner probe, ±3 °F wet bulb, direction+value only | `vectors.json` already carries `sensitivityCases`; the harness skips them with a notice. Porting the full analysis into `engine.js` and flipping the skip into an assertion is the queued next parity task — a good first run for the agent. |
| Notes export | `NotesExport`: title line, units line, wet-bulb column, midnight dividers, footers | simplified `notesText()` tab table | Web obs records don't retain wet-bulb/humidity; align when they do. |
| NWS spot block | `SpotObservationsRenderer` aligned ASCII table | simplified `spotText()` (currently unreachable from the UI) | Same constraint as above. |
| Radio overrides | `forceLocation` / `suppressLocation` operator toggles | no UI affordance | Vectors pin the common path; add with the UI when ported. |
| Month-group caption | "Feb–Mar–Apr & Aug–Sep–Oct" | "Feb Mar Apr Oct" (drops Aug–Sep) | Display copy only; fix with any app.js touch. |
| Obs timestamps | real `Date`s; a shift can span local midnight (multi-sheet export) | minutes-of-day + per-shift date | Web model is day-scoped by design; xlsx vectors use one-day shifts. |
| Logged month | `pendingObs` derives month from the wall clock at log time | `monthForLog()` reads the shift's own date (`shiftDateMs`) | Consequence of the day-scoped model: a shift carried across a month boundary logs the shift's month. Aligns when timestamps do. |
| IMET wet-bulb column | column C written from the obs's frozen `HumidityResult` | header present, column never written — web obs don't retain the wet bulb | Same root cause as the Notes-export row; vectors carry no wet-bulb obs, so the harness can't see it. Align when web obs retain humidity. |
| "Recorded calm" wind | `nil` (not recorded) vs `.lightVariable` (recorded calm) are distinct — cell omitted vs "Light/Variable" | one shape: `high<=0 && gust<=0` reads as not recorded | A deliberate calm reading can't appear in a web broadcast/export. Align with the wind-model port. |
| Sheet-name truncation | `prefix(31)` counts grapheme clusters; empty-book fallback uses the **earliest** shift | `slice(0,31)` counts UTF-16 units (can split a surrogate pair); fallback uses the **last** entry | Divergent only for non-BMP division names near 31 chars or multi-empty-shift books — both unreachable from the UIs; vectors are ASCII, one-shift. Fix web-side with any engine touch. |
| GPS site autofill | `SiteElevation` (round to 100 ft, band-straddle check) + `GeoPoint.isValid`, driven by CoreLocation in `SiteLocationProvider` | site elevation and lat/long typed only; no Geolocation API use | **Deliberately not ported yet.** These are device-sensor normalization rules, not IRPG calculation — nothing in `engine.js` calls them, so porting now would add dead code to the shipped PWA and force every field device to refetch its cache for no user benefit. Port them together with web Geolocation autofill, in the same change. Not in `vectors.json`, so parity CI stays green and honest meanwhile. |

## The structural endgame (if wanted later)

`PlateworksCore` imports only Foundation, so it can compile to WebAssembly
(SwiftWasm) and replace `engine.js` outright — one implementation, parity by
construction. The costs (multi-MB first load on fireline connections, a build
step, a less-boring toolchain) are why this repo currently prefers the
vectors-plus-agent approach. If drift pressure ever outgrows it, the
conformance suite built here becomes the acceptance test for that migration.
