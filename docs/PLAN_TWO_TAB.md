# Implementation plan — two-tab restructure

Task-level plan for the work specified in [`UX_TWO_TAB.md`](UX_TWO_TAB.md),
in the idiom of [`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md): each PR
states what it changes, how it is **verified**, and whether it can be done in
a cloud session or needs a Mac. The spec owns the *what* and *why*; this
document owns the *order, tasks, and proof*. Sign-off on the spec's §1 list
precedes any PR here.

## Status

| PR | Contents | State |
|---|---|---|
| 1 | Shell + Humidity merge (native) | **In review** |
| 2 | Obs loop — sheet, receipt, success screen, site factors (native) | **In review** |
| 3 | Web twin + month-freeze parity fix | **In review** |
| 4 | Docs — CLAUDE.md guardrail, `DESIGN.md` §4, README, App Store copy | **In review** |

Book mode (spec §10) is **not in this plan** — it gets its own spec first.

The four slices are landing as sequential commits on one review branch rather
than four separate branches, so "PR" below reads as "reviewable slice". The
ordering constraints are what matter and they hold either way; the
`DESIGN.md` / `CLAUDE.md` copy in slice 4 still lands last, after the code it
describes.

---

## Sequencing constraints worth respecting

**A. PR 1 before PR 2 — the sheet embeds what PR 1 finalizes.** The capture
sheet (spec §7) embeds `WeatherInputGroup`, and PR 1 is what gives that group
its final wet-bulb shape (derived row + Alaska toggle). Landing PR 2 first
means re-touching the sheet when PR 1 lands. Both also edit `WatchView`;
serializing them avoids a needless conflict on the busiest file.

**B. Port once.** PR 3 ports the *sum* of PRs 1–2 to the web twin in one
pass. Porting after each native PR doubles the web work and doubles the
service-worker cache bumps field devices must absorb.

**C. Identifier freeze.** The preserved accessibility identifiers (spec §11)
anchor `PlateworksIgnitionUITests`. PRs 1–2 move controls into the sheet but
keep their identifiers verbatim; only the Humidity suite's identifiers die,
and they die with their suite in the same PR — never orphaned.

**D. The parity agent will notice.** When PRs 1–2 land on `main` without a
web counterpart, `.github/workflows/web-parity-agent.yml` opens a draft port
PR. Either have PR 3 ready to open immediately behind PR 2's merge, or adopt
the agent's draft as PR 3's starting point — both are fine; two competing
ports are not.

```
Spec sign-off ──► PR 1 (shell + merge) ──► PR 2 (Obs loop) ──► PR 3 (web twin) ──► PR 4 (docs)
                                                    │
                                                    └──► Mac visual pass (batch with
                                                         IMPLEMENTATION_PLAN 2.6)
```

---

## PR 1 — Shell + Humidity merge (native)

Implements spec §4 and §5.

**Tasks.**

1. `IgnitionModel` gains `alaska: Bool`, persisted under `ignition.alaska`
   and **seeded once from the orphaned `humidity.alaska` key** — the toggle
   is a sticky regional setting; an Alaska crew shouldn't lose it to a
   restructure. Move `HumidityModel.label(for:)`
   (`Features/Humidity/HumidityModel.swift:38–40`) with it.
2. `IgnitionModel` exposes its wet-bulb-mode `HumidityResult` (dew point,
   WB depression are already computed by `Psychrometrics.compute`; today the
   model surfaces only the RH).
3. `WeatherInputGroup` wet-bulb mode: the derived-RH card grows into the
   derived row (RH primary in accent · dew point · WB depression, with the
   psychrometric-estimate caption), and the Alaska toggle joins the
   elevation-band chip row. Both stay contained at the end of the group
   (`UX_WORKFLOW.md` §4.3).
4. Delete `Features/Humidity/` (both files), `IgnitionModel.applyHumidity`
   (`Features/Ignition/IgnitionModel.swift:201`), and the Humidity tab +
   `Tab.humidity` + hand-off closure in `App/RootView.swift:19,33–42`.
5. Shared-cue copy: `SHARED · WATCH` → `SHARED · OBS`
   (`Features/Ignition/IgnitionView.swift:82`).
6. Tests: delete the Humidity unit + UI suites in the same commit; add
   `IgnitionModel` tests for the alaska flag, the seeded migration, and the
   exposed `HumidityResult`; add a UI test that wet-bulb mode shows the
   derived row and `alaska-toggle` while direct mode shows neither.

**Verification.** Entirely CI: the `app-build` job (XcodeGen → iOS Simulator
+ macOS builds → both test bundles). No core change, so the Linux job and
`conformance/check-web.js` must pass **untouched** — any vector churn here is
a defect. **Size.** ~1 day. **Risk.** Low — deletions plus one contained
group change. **Environment.** Cloud. The derived row's layout at large
Dynamic Type needs eyes on a Mac eventually — batch it into the visual pass
(below), don't block the PR on it.

---

## PR 2 — Obs loop (native)

Implements spec §6, §7, §8, §9. The biggest and riskiest PR in this plan.

**Tasks.**

1. **Site factors into `SiteEditor`** (spec §6): the three chip rows above
   the Confirm gate, `⧉ SHARED · IGNITION` cue. `SiteEditor` today binds only
   `WeatherWatchModel`; its signature grows an `IgnitionModel` (the caller,
   `WatchView.swift:114`, already holds both).
2. **One observation form, two modes** (spec §7): generalize `ObsEditSheet`
   (`Features/Watch/WatchView.swift:922–1052`) into an `ObsFormSheet` with a
   capture mode and an edit mode, per the spec's mode table. Capture mode
   embeds `WeatherInputGroup` (write-through to shared state — dismissing
   without logging keeps weather edits *by design*: it is the live reading,
   and the receipt is what makes that safe). Edit mode keeps today's isolated
   `@State` seeding.
3. **Move the obs-time machinery into the sheet wholesale**: `ObsTimeField`,
   the auto-seed loop, and `obsTimeIsManual`'s minute-granularity comparison
   (`WatchView.swift:216–231`). Two documented bugs live in this logic's
   history — the 0900-stamp staleness bug and the text-field echo that
   defeated exact comparison — so it moves **unmodified**, with one lifecycle
   change: seeding happens on sheet presentation rather than view appear.
   The freshness strip and future-time strip move in with it
   (`WatchView.swift:523–549`).
4. **Freeze receipt** (spec §8): a pure `receiptLine(for:)` builder on
   `WeatherWatchModel` beside `pendingObs`, rendered above the commit button.
5. **Success state** (spec §9): on commit the sheet swaps to the frozen
   `broadcastText`, large + high-contrast, with Copy and Done. Log haptic
   unchanged.
6. **Log bar presents the sheet**; the site-confirmation gate stays on the
   bar (`WatchView.swift:763,808`), so the sheet never opens unconfirmed.
   The capture card leaves the scroll.
7. **Deep link**: `.logObservation` (`App/RootView.swift:65–71`) selects Obs
   *and* presents the capture sheet.
8. Tests — the ones that matter:
   - **Receipt round-trip** (unit): build `pendingObs`, log it, assert every
     receipt field equals the frozen obs's inputs — the spec's acceptance
     §13.6, and the test that keeps the receipt honest forever.
   - Obs-time semantics (unit-level where the model allows): manual override
     survives a tick; a log hands the time back to the clock.
   - UI flow: Log → sheet → adjust → commit → success screen → Done → new
     hero; edit flow unchanged; gated flow (unconfirmed site never opens the
     sheet); site chips present in Site & radio.

**Verification.** CI `app-build` as above; zero vector churn. **Size.** 2–3
days. **Risk.** Medium — concentrated in task 3 (time-seeding semantics) and
in test migration; both are why the machinery moves unmodified and the
receipt gets a round-trip test rather than a screenshot. **Environment.**
Cloud. Receipt wrapping at `.accessibility2` and success-screen type scale
need the Mac visual pass.

---

## PR 3 — Web twin + parity fix

Ports PRs 1–2 to `web/` and fixes the divergence the spec recorded (§3 P4).

**Tasks.**

1. `web/index.html`: two-button tab bar (lines 216–219).
2. `web/app.js`: delete `renderHumidity` and the `hDry`/`hWet`/`hBand`/
   `hAlaska` state + `useInIgnition` handler (`app.js:46,180–198,470–471`);
   `weatherGroup` gains the derived row and an Alaska control (the web's
   first — it ships none today); site chips into the site group; generalize
   the edit modal (`app.js:344–367`) into the two-mode form; delete the
   capture card (`app.js:305–316`); receipt; success state (retire the log
   toast).
3. **Month-freeze fix**: `logObs` freezes `S.month` (`app.js:402,405`);
   derive the month from the observation's date instead, matching
   `WeatherWatchModel.pendingObs` (`WeatherWatchModel.swift:170`). This is a
   behavior change for an operator logging with a manual month override
   active — call it out as the bug fix it is in the PR body.
4. `localStorage` hygiene: the loader's `Object.assign` already tolerates the
   stale `h*` fields; prune them on load so they don't persist forever.
5. `web/sw.js`: `CACHE` `badwater-ignition-v4` → `-v5` — without it, field
   devices keep serving the three-tab app offline indefinitely.

**Verification.** `node conformance/check-web.js` must stay green
**untouched** (it gates `engine.js`, which this PR must not touch). UI
verification is real and local: the PWA has no build step, and the container
ships Chromium + Playwright — script the loop (open page → confirm site →
Log → sheet → commit → success → hero updated) and keep the script in the PR
as the smoke test. **Size.** ~1 day. **Risk.** Low-medium; the month fix is
the only behavior change. **Environment.** Cloud, fully — this is the one PR
provable end-to-end without CI.

---

## PR 4 — Docs

1. `CLAUDE.md`: the guardrail sentence enumerates two tabs (**Ignition ·
   Obs**) — the guardrail's intent (Obs is a feature, not the brand; never
   re-plural the brand) is restated unchanged. Map-of-repo table gains
   `UX_TWO_TAB.md` / this plan.
2. `DESIGN.md`: §4 rewritten to the two-tab structure (Ignition absorbs
   §4.2's content; §4.3 documents the sheet loop); §5 gains `ObsFormSheet`,
   the receipt, and the success screen; §7's Book-mode line points at spec
   §10's promotion.
3. `README.md:29` and `docs/APP_STORE.md:30`: both describe the Humidity tab
   and the one-tap hand-off; rewrite around wet-bulb mode.
4. `UX_TWO_TAB.md` status → **Implemented**; this plan's status table flips.

**Verification.** Reciprocal cross-references intact; every cited path
exists. **Size.** Half a day. **Environment.** Cloud.

---

## The Mac visual pass (not a PR — a session)

The three visual judgments this restructure creates, none blocking a merge,
all wanting eyes before TestFlight: the derived row at large Dynamic Type
(PR 1), receipt wrapping at `.accessibility2` (PR 2), success-screen type
scale in sunlight-contrast terms (PR 2). Batch them with
`IMPLEMENTATION_PLAN.md` **2.6** (Dynamic Type on readouts) — same session,
same judgment, one device.

---

## Environment split

This authoring container has **no Swift toolchain**, unlike the session
`IMPLEMENTATION_PLAN.md` was written in — so native work here iterates
through CI's `app-build` job rather than local `swift test`. That is slower
per cycle but sound: every native change in this plan is provable by tests
CI already runs.

| Cloud session (CI proves it) | Needs a Mac / device |
|---|---|
| PR 1 entirely | Derived-row layout at accessibility sizes |
| PR 2 entirely (receipt round-trip + UI flows run in CI) | Receipt wrap, success-screen scale — the visual pass |
| PR 3 entirely — **locally provable**, Playwright smoke included | — |
| PR 4 entirely | — |

---

## Suggested order

1. **Spec sign-off** — the seven decisions in `UX_TWO_TAB.md` §1.
2. **PR 1** (small, derisks the shell, finalizes `WeatherInputGroup`).
3. **PR 2** (the big one; do it immediately after 1 while the Watch tests
   are fresh).
4. **PR 3** ready to open behind PR 2's merge — pre-empting or adopting the
   parity agent's draft.
5. **PR 4**, closing the loop; the spec flips to Implemented.
6. **Mac visual pass** batched with 2.6, before TestFlight.

Against the charter's milestones: **all of this lands before TestFlight.**
The restructure changes what every screenshot shows and what every first
external tester learns; shipping a three-tab beta and then deleting a tab is
the wrong order. It is independent of `PLAN_WIDGET_AND_WATCH.md` (glance
surfaces follow the record, which doesn't change shape) — the two streams
can proceed in parallel without stepping on each other.
