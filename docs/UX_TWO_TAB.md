# Badwater Ignition — Two-Tab Restructure

| | |
|---|---|
| **Status** | Proposed — awaiting sign-off; implementation follows the PR slicing in §12, task-planned in `PLAN_TWO_TAB.md`. |
| **Scope** | Collapse the three-tab shell to two tabs (Ignition · Obs); absorb the Humidity screen into Ignition's weather group; restructure the Obs hourly loop around a capture sheet, a freeze receipt, and a post-log broadcast screen; expose the site factors on Obs; promote Book mode from v2 candidate to the Ignition tab's marquee follow-on. |
| **Non-goals** | No calculation changes — `Sources/PlateworksCore/` and `web/engine.js` are untouched, and no conformance vectors regenerate. No widget, watch-app, or Live Activity changes (they follow the record, which doesn't change shape). No visual-brand changes — colors, type, and component styling stay as specified in `DESIGN.md`. |
| **Companions** | `docs/PLAN_TWO_TAB.md` (the task-level implementation plan for this spec) · `DESIGN.md` (visual system) · `docs/UX_WORKFLOW.md` (the shipped Ignition restructure this builds on) · `docs/PLAN_WIDGET_AND_WATCH.md` (the volatile-vs-frozen design line) |

Every decision below is grounded in the shipped code, cited as `file:line`
against the tree at the time of writing. Wireframes are drawn at iPhone SE
width. The native app leads; the web twin follows (`docs/PARITY.md`).

---

## 1. Sign-off list

Seven decisions that need assent:

1. **Two tabs — Ignition · Obs.** The Humidity tab is deleted; launch stays on
   Ignition. → §4
2. **Humidity is absorbed into the WEATHER group's wet-bulb mode** (dew point,
   wet-bulb depression, Alaska toggle), and the separate humidity scratchpad
   state is accepted as lost. → §5
3. **The site-factor chips join the Site & radio block on Obs**, above the
   Confirm-site gate, carrying the `SHARED` cue. → §6
4. **Capture moves into a sheet** unified with the existing edit form; the Obs
   scroll becomes record review only. → §7
5. **A freeze receipt** — one line stating everything the Log tap will freeze —
   sits directly above the commit button. → §8
6. **The post-log moment presents the broadcast script full-screen.** → §9
7. **Book mode is promoted** from v2 candidate to the Ignition tab's next
   feature, specified separately. → §10

---

## 2. The operator's loop

The app's real test is not the tab count — it is one loop repeated roughly
twelve times a shift by a tired person in gloves and glare. The structure
below is evaluated against that loop.

- **Start of shift, once.** Enter the radio/IMET header (addressee, location,
  division, elevation, coordinates), review the site factors, **Confirm site**.
  Pre-filled from yesterday, re-armed each shift
  (`WeatherWatchModel.needsSiteConfirmation`,
  `App/PlateworksIgnition/Features/Watch/WeatherWatchModel.swift:145`) — the
  pilot's-checklist pattern, already right.
- **Hourly, ~12×.** Sling the psychrometer or read the Kestrel → enter dry
  bulb, RH (or wet bulb), wind → check the number → **Log** → read the
  broadcast script over the radio. Steppers are the correct input here:
  readings drift by small deltas hour to hour, so the loop is a handful of
  big-target taps, no keyboard.
- **Ad hoc.** "How bad is it right now / what if" — answered by the pinned
  `PIGSummaryBar` the moment the app opens
  (`App/PlateworksIgnition/Features/Ignition/IgnitionView.swift:25`).
- **End of shift.** Export the IMET `.xlsx`, start a new shift.

The two-tab split maps one tab to each recurring question: **Ignition = check
now**, **Obs = keep the record**. That is also the volatile-vs-frozen line the
project's guardrails already draw.

---

## 3. Problems

Five, all confirmed in source:

**P1 — The third tab duplicates a capability Ignition already ships.** The
Humidity screen computes RH from dry/wet bulb + elevation band
(`App/PlateworksIgnition/Features/Humidity/HumidityView.swift`) — and so does
Ignition's *From wet bulb* humidity-source mode, via the same
`Psychrometrics.compute`, inside the shared weather group
(`App/PlateworksIgnition/Features/Shared/WeatherInputGroup.swift`). The only
things Humidity owns exclusively are the dew-point and wet-bulb-depression
readouts (`HumidityView.swift:27–34`), the Alaska elevation-thresholds toggle
(`HumidityView.swift:78–87`), and its own scratch state
(`HumidityModel.swift:14–19`). The "Use in ignition calc" hand-off
(`HumidityView.swift:89–101`, `IgnitionModel.applyHumidity`,
`App/PlateworksIgnition/Features/Ignition/IgnitionModel.swift:201`) exists
only to bridge a split this spec removes.

**P2 — The capture card is buried below the entire record.** The Obs body
renders, in order: header, persistence warning, due strip, hero, broadcast,
trend, shift log, site & radio, **then** the capture card
(`App/PlateworksIgnition/Features/Watch/WatchView.swift:100–120`; same order
in the web twin, `web/app.js:336–341`). The most frequent action in the app —
editing the pending reading, every hour — requires scrolling past everything
else to reach it. The pinned Log bar commits the obs
(`WatchView.swift:123,762–815`) but cannot edit it.

**P3 — The moment after logging is misplaced.** The instant an obs is logged,
the operator needs the radio script — and they are at the bottom of the
scroll while the broadcast panel is near the top
(`WatchView.swift:108,329–356`). A scroll-hunt at the moment of radio
pressure, twelve times a shift.

**P4 — The what-if leak.** Ignition is the sandbox ("what would the south
aspect read?") but the sandbox writes to the same shared state the next log
freezes: `pendingObs` reads `ignition.aspect`, `ignition.slope`, and
`ignition.elevationDelta` (`WeatherWatchModel.swift:172`), and none of the
three is visible anywhere on the Obs screen — the Site & radio block collects
the IMET header only (`App/PlateworksIgnition/Features/Watch/SiteEditor.swift`),
while its gate says "Review the site factors, then confirm"
(`SiteEditor.swift:69–70`). Scout a different aspect mid-shift, forget to set
it back, and the next hourly obs freezes and broadcasts the wrong slope's
PIG. (Month and time band are safe natively — `pendingObs` derives both from
the obs clock, `WeatherWatchModel.swift:152,170–171`. The web twin freezes
`S.month` instead, `web/app.js:402` — a parity divergence the web PR fixes,
§12.)

**P5 — Capture and edit are two different UIs for the same form.** The
pending capture card (`WatchView.swift:496–517`) and the `ObsEditSheet`
(`WatchView.swift:922–1052`; modal twin at `web/app.js:344–367`) collect the
identical fields — time, dry bulb, RH/wet bulb, wind, note — with different
layouts, different affordances, and duplicated future-time guards.

---

## 4. Spec A — The two-tab shell

`RootView` drops the Humidity tab and its hand-off closure
(`App/PlateworksIgnition/App/RootView.swift:19,33–55`); the web tab bar drops
its first button (`web/index.html:216–219`, `web/app.js:180–198`). Launch
stays on Ignition. The `logObservation` deep link keeps opening the Obs tab
(`RootView.swift:65–71`) and now also presents the capture sheet (§7) — the
intent's whole purpose is to start a log.

**Naming guardrails are untouched:** the Obs tab keeps the name "Obs", the
brand stays "Badwater Ignition" (singular). The CLAUDE.md guardrail sentence
that enumerates *three* tabs is updated to enumerate two in the docs PR
(§12); the guardrail's intent — Obs is a feature, not the brand — is
unchanged.

What is deleted outright: `Features/Humidity/` (both files), the
`onUseInIgnition` closure, `IgnitionModel.applyHumidity`
(`IgnitionModel.swift:201`), the web `renderHumidity` and its
`hDry`/`hWet`/`hBand`/`hAlaska` state (`web/app.js:46,180–198,470–471`).
Orphaned persistence keys (`humidity.*` in UserDefaults, stale fields in the
web `localStorage` blob) are harmless on both platforms — both loaders ignore
unknown keys.

> **Decision:** two tabs, Ignition · Obs, launch on Ignition; Humidity's
> screen, model, state, and hand-off are deleted.

---

## 5. Spec B — Humidity absorbed into the WEATHER group

The WEATHER group's *From wet bulb* mode gains Humidity's three exclusive
capabilities, placed with the existing wet-bulb-only rows (contained at the
end of the group, per `docs/UX_WORKFLOW.md` §4.3):

1. **Derived stats.** The derived-RH card grows into a derived row: **RH**
   (the value that feeds the chain, kept visually primary in accent teal) ·
   **dew point** · **WB depression**. The psychrometric disclaimer line
   ("verify against your belt weather kit tables",
   `HumidityView.swift:103–108`) becomes this row's caption.
2. **Alaska toggle.** Joins the elevation-band chip row it modifies. It only
   relabels which elevations map to which band — `Psychrometrics.compute`
   takes the band directly (`HumidityModel.swift:32–34,38–40`) — so this is a
   labeling control and belongs beside the labels it changes. The web twin
   currently ships no Alaska control at all (`web/app.js:180–198` renders
   none despite carrying `hAlaska` state) — the merge is where it gains one,
   closing that parity gap.
3. **Nothing else.** The 72 pt RH "brand moment" (`HumidityView.swift:55–70`)
   is consciously demoted to the derived row: on the merged screen the
   headline number is the PIG in the pinned summary bar, and two competing
   hero numerals on one screen would fight. If the brand moment is missed,
   the derived row's RH can render a size up in wet-bulb mode — copy owner's
   call at implementation.

**Direct-RH mode — the common case (Kestrel-style meters) — shows none of
this.** The everyday screen gets *simpler* than today: dry bulb + RH + wind,
then the calendar and site groups.

**Accepted loss — the scratchpad.** Today an operator can compute a courtesy
RH for someone else without touching the live estimate, because Humidity has
separate state. Merged, a wet-bulb check moves the live inputs. Nothing
frozen is affected — logged obs are immutable records — and the readings are
two stepper-taps from restored. This is the price of the third tab, and this
spec pays it deliberately.

**Merged Ignition, wet-bulb mode** (direct mode shows only the first three
rows of the group):

```
┌──────────────────────────────────────┐
│ UNSH 80%   SHD 60%           EXTREME │ ← pinned PIGSummaryBar (unchanged)
├──────────────────────────────────────┤
│ Ignition                IRPG P.44–49 │
│ WEATHER · IRPG TABLE A   ⧉ SHARED·OBS│
│ ┌──────────────────────────────────┐ │
│ │ HUMIDITY SOURCE (Direct)(Wet blb)│ │
│ │ [DRY BULB 90°F]  [WET BULB 62°F] │ │
│ │ ELEV BAND · 27 INHG   [AK ⚪︎]    │ │ ← Alaska joins the row it relabels
│ │ (<2k)(2-4k)(4-6k)(6-8k)(8k+)     │ │
│ │ RH 14% · DEW 34°F · DEPR 28°F    │ │ ← Humidity's readouts, absorbed
│ └──────────────────────────────────┘ │
│ [wind rows]                          │
│ CALENDAR · TIME · TABLES B/C/D       │
│ SITE · CORRECTIONS       ⧉ SHARED·OBS│
│ REF FM → CORR → FFM → results        │
└──────────────────────────────────────┘
```

The shared-weather cue copy changes from `SHARED · WATCH` to `SHARED · OBS`
on Ignition (and stays `SHARED · IGNITION` on Obs) — the cue names the tab as
the operator sees it, and "Watch" is internal vocabulary
(`IgnitionView.swift:82`).

> **Decision:** wet-bulb mode gains the derived-stats row and the Alaska
> toggle; the hand-off button and the scratchpad die; direct mode is
> untouched.

---

## 6. Spec C — Site factors on Obs

The Aspect, Slope, and Elevation-vs-weather-site chip rows join the **Site &
radio** block (`SiteEditor.swift`), directly **above** the Confirm-site gate,
bound to the same shared `IgnitionModel` state the Ignition tab shows
(`IgnitionView.swift:125–137`) and carrying the `⧉ SHARED · IGNITION` cue.

Placement rationale: they are per-shift *site facts*, not per-observation
readings — they belong with the header the shift confirms, not in the capture
sheet the operator races through hourly. And the gate's own copy ("Review the
site factors, then confirm") finally shows the factors it asks about,
resolving P4's visibility half; the receipt (§8) resolves its
moment-of-freeze half.

```
│ SITE & RADIO · IMET HEADER           │
│  addressee / location / division     │
│  site elevation / lat / long         │
│  ASPECT (N)(E)(S)(W)  ⧉ SHARED·IGNITION
│  SLOPE (0–30%)(31%+)                 │
│  ELEV VS WX SITE (Blw)(Lvl)(Abv)     │
│  🛡 Review the site factors → Confirm │
```

> **Decision:** the three site-factor chip rows render in Site & radio, above
> the gate, shared-cued — not in the capture sheet.

---

## 7. Spec D — Capture becomes a sheet; the scroll becomes the record

The pending capture card leaves the scroll. The pinned **Log Observation**
bar (`WatchView.swift:762–815`) becomes the *entry point*: tapping it
presents a capture sheet; the sheet's own commit button does the freeze. The
Obs scroll is then pure record review — due strip, hero, broadcast, trend,
shift log, site & radio, export, history — and the hourly loop no longer
scroll-hunts (P2).

**One form, two entry points.** The sheet is the existing `ObsEditSheet`
form (`WatchView.swift:922–1052`) generalized into one observation form with
two modes:

| | Capture mode | Edit mode |
|---|---|---|
| Seeded from | live shared `IgnitionModel` + clock | the frozen obs (isolated `@State`, as today) |
| Weather edits | write through to shared state (it *is* the live reading) | isolated — never touch the live tab (`WatchView.swift:915–920`) |
| Time | auto-seeded, manual-override detection carried over (`WatchView.swift:216–231`) | the obs's own timestamp |
| Commit | freeze receipt (§8) + **Log Observation** → `logObs` | **Save** → `updateObs` |
| Extras | freshness strip, future-time strip (both move in from the card, `WatchView.swift:523–549`) | future-time strip (already present) |

This deletes the duplicated capture/edit layouts (P5) the same way
`WeatherInputGroup` deleted the duplicated weather controls: one source file,
two callers, the forms *can't* drift. The web twin makes the same move — its
edit modal (`web/app.js:344–367`) generalizes to both modes and the capture
card (`web/app.js:305–316`) is deleted.

Details that carry over or change:

- The **live PIG preview** stays in the sheet header (today's
  `→ PIG 12 / 9`, `WatchView.swift:502–505`).
- The **site-confirmation gate** moves up a level: an unconfirmed site
  disables the Log bar exactly as today (`WatchView.swift:763,808`) — the
  sheet never opens on an unconfirmed site, so the gate's guarantee is
  unchanged.
- The **due strip stays on the scroll** (it is record state, not capture
  state) and the existing cadence notification (`ObsCadenceScheduler`) is
  untouched — the reminder fires, the operator taps Log, the sheet opens.
- The `logObservation` **App Intent** presents the sheet on arrival (§4) —
  the intent means "start a log", and today it strands the operator at the
  top of the scroll with the capture card six sections down.
- **Guardrail check:** "Freezing a reading requires the capture card"
  (CLAUDE.md) — the sheet *is* the capture card, presented instead of
  embedded. No new surface gains the ability to freeze.

```
   Obs scroll (record only)          Capture sheet (on Log tap)
┌──────────────────────────┐      ┌──────────────────────────┐
│ Obs           3 OBS SHIFT│      │ Pending obs   → PIG 12/9 │
│ ◷ Next obs 15:30 · 22 min│      │ ◷ Weather read 2 min ago │
│ [Latest hero + radio line]│     │ [OBS TIME 14:58  −5m +5m]│
│ [Broadcast · Copy]        │     │ [DRY BULB]  [RH / WET]   │
│ [Trend]                   │     │ [WIND LOW]  [WIND HIGH]  │
│ [Shift log]               │     │ [note…]                  │
│ [Site & radio + factors]  │     │──────────────────────────│
│ [Export] [History]        │     │ FREEZES: 90° · 8% · SW 3–6│
│ [Start new shift]         │     │ · JUL · S · 31%+ · LEVEL │
├──────────────────────────┤      │ [ Log Observation ▸ ]    │
│ [ Log Observation · 14:58]│     └──────────────────────────┘
└──────────────────────────┘
```

> **Decision:** capture is a sheet opened by the pinned Log bar, sharing one
> observation form with edit; the scroll carries only the record.

---

## 8. Spec E — The freeze receipt

Directly above the sheet's commit button, one fixed-height line states
**everything the tap will freeze**:

```
90°F · 8% (direct) · SW 3–6 G12 · Jul · 1458 → 1400–1559 · S · 31%+ · Level
```

— dry bulb, effective RH with its source, wind, month, the obs time **and
the IRPG time band it resolves to**, aspect, slope, elevation delta. Mono
caption (`fieldLabel()` idiom), values in ink, wrapping to two lines under
Dynamic Type rather than truncating; a truncated receipt is worse than none.

This is the receipt-before-payment pattern, and it is the cheap, principled
close of the what-if leak (P4): the stale aspect from a mid-shift what-if is
*visible at the exact moment it matters*, on the one surface designated for
freezing. It also makes the clock-derivation rule legible — the operator sees
that the band came from the obs time, not from the Ignition tab's time chips.

The heavier alternative — a sandboxed "scout mode" on Ignition that
auto-reverts what-if changes — is **deferred, not designed**: it adds a mode,
a revert affordance, and a new failure class (forgetting you're sandboxed)
for the residual risk the receipt doesn't already cover. Revisit only if
field reports show the receipt isn't enough.

Accessibility: one combined element — *"Will freeze: 90 degrees, 8 percent
relative humidity, wind southwest 3 to 6 gusting 12, July, 14:58, band 1400
to 1559, south aspect, steep slope, level elevation."* New identifier:
`freeze-receipt`.

> **Decision:** a one-line, fixed-height receipt above the commit button,
> enumerating every frozen input; scout mode deferred.

---

## 9. Spec F — The broadcast is the success screen

On commit, the sheet's content is **replaced by the frozen broadcast
script** — the thing the operator needs next, at the moment they need it
(P3):

- The script full-width in large type (`readout`-scale, not body), maximum
  contrast — the boarding-pass pattern: the artifact about to be *used* gets
  the dedicated moment. Read over the radio directly from this screen, in
  sunlight.
- A **Copy** action (≥ 48 pt) and a **Done** dismiss. Done returns to the Obs
  scroll, where the new obs is the hero.
- The existing log haptic fires as today (`WatchView.swift:66–70,766`).
- This is a *presentation* of the already-frozen `obs.broadcastText`
  (`WeatherWatchModel.swift:198–202`) — rendered once at log time, never
  recomputed. Volatile-vs-frozen line: untouched.
- Web twin: the sheet swaps to the same success state; the existing toast is
  retired on Obs.

> **Decision:** commit replaces the sheet with the frozen script, big and
> high-contrast, with Copy; Done lands on the updated record.

---

## 10. Spec G — Book mode, promoted

`DESIGN.md` §7 lists "Book mode" as a v2 candidate: render the actual IRPG
table with the resolved cell highlighted. This spec promotes it to the
**Ignition tab's next feature after the merge**, because on a two-tab app the
Ignition tab's whole job is *trustworthy estimation*, and position-in-the-
field is the industry-leading presentation for safety lookups (avalanche
danger roses, aviation performance charts):

- It is the chain strip's show-your-work made spatial — the trust feature's
  ultimate form.
- It makes the existing sensitivity envelope self-evident: the neighboring
  cell the reading might slide into is *right there*, adjacent.
- It doubles as training — operators verify the app against the printed page
  cell-for-cell, which is this project's entire correctness posture.

Direction only; it gets its own spec (table pagination, cell-highlight
accessibility, landscape) and its own PR. Nothing in §§4–9 depends on it.

**Rejected, not deferred — the hourly PIG strip.** A weather-app-style row
showing PIG across all time bands was considered for glanceability and
rejected on safety grounds: it would project the *current* temp and RH across
the day, and the whole reason obs are hourly is that those change. A
same-readings-across-time strip understates the afternoon peak in a way no
caption fixes at glance speed. The honest time view already exists — the Obs
trend chart, built from real frozen readings (`WatchView.swift:375–399`).

**Also rejected — folding Ignition into Obs** (keeping Humidity): buries the
primary readout inside the logging workflow and keeps the tab with the least
reason to exist.

> **Decision:** Book mode is the merged Ignition tab's marquee follow-on,
> specified separately; the hourly strip is rejected on safety grounds.

---

## 11. Accessibility & motion

- **Identifiers preserved verbatim** — they anchor
  `App/PlateworksIgnitionTests` and the UI tests: `log-observation`,
  `obs-time`, `obs-time-field`, `obs-note`, `weather-freshness`,
  `mark-weather-current`, `obs-time-future`, `edit-save`, `edit-cancel`,
  `pending-pig`, `broadcast-script`, `copy-broadcast` — now inside the sheet
  where applicable. Deleted with their screen: `rh-readout`,
  `use-in-ignition`. New: `freeze-receipt`, `capture-sheet`,
  `broadcast-success`, `alaska-toggle` (the toggle's first identifier —
  `HumidityView.swift:78–87` ships without one).
- **Dynamic Type:** the receipt wraps (never truncates); the success-screen
  script scales down before it clips; both validated to `.accessibility2`.
- **Reduce Motion:** sheet presentation is the platform's; the
  commit-to-success swap is a crossfade under Reduce Motion.
- **Haptics:** unchanged (`.success` on log, `.warning` on delete).

---

## 12. Implementation appendix

The slicing below is expanded to task level — with per-PR verification,
sizes, risks, and the cloud-vs-Mac split — in
[`PLAN_TWO_TAB.md`](PLAN_TWO_TAB.md).

**Order:** native first, web twin second (`docs/PARITY.md`). No
`PlateworksCore` change ⇒ no vector regeneration; `node
conformance/check-web.js` must stay green untouched. The web PR bumps
`CACHE` in `web/sw.js`.

| PR | Contents |
|---|---|
| **PR 1 — shell + merge (native)** | `RootView` two-tab shell; `WeatherInputGroup` gains derived-stats row + Alaska toggle (state moves into `IgnitionModel`); delete `Features/Humidity/` and `applyHumidity`; shared-cue copy `WATCH`→`OBS`. App-target unit + UI tests updated (Humidity suite deleted, not skipped). |
| **PR 2 — Obs loop (native)** | Site factors into `SiteEditor`; observation form unification (capture sheet + edit mode from `ObsEditSheet`); freeze receipt; broadcast success screen; deep link presents the sheet; capture card deleted. |
| **PR 3 — web twin** | `index.html` tab bar; `app.js`: humidity tab deleted, weather group gains derived row + Alaska, site chips into the site group, capture/edit modal unification, receipt, success state; **fix the month-freeze parity divergence** (`web/app.js:402` freezes `S.month`; native freezes the clock month, `WeatherWatchModel.swift:170`); `sw.js` cache bump. Gated by `conformance/check-web.js`; the parity agent may draft it. |
| **PR 4 — docs** | CLAUDE.md guardrail (three tabs → two; Obs-naming intent unchanged); `DESIGN.md` §4 rewrite; `README.md` + `docs/APP_STORE.md` copy (both describe the Humidity tab and the one-tap hand-off); mark this spec **Implemented**. |

**Files touched (native):** `App/RootView.swift`,
`Features/Shared/WeatherInputGroup.swift`, `Features/Ignition/IgnitionModel.swift`,
`Features/Ignition/IgnitionView.swift`, `Features/Watch/WatchView.swift`,
`Features/Watch/SiteEditor.swift`, `Features/Watch/WeatherWatchModel.swift`
(receipt string builder), `Intents/PlateworksAppIntents.swift` (deep link),
deletions in `Features/Humidity/`.

**Out of scope, restated:** Book mode (own spec), scout mode (deferred),
widget/watch/Live-Activity surfaces (unchanged), anything in
`Sources/PlateworksCore/` or `web/engine.js`.

---

## 13. Acceptance criteria

A future implementation PR satisfies this spec when:

1. The app shell presents exactly two tabs — Ignition, Obs — launching on
   Ignition, on both platforms.
2. Wet-bulb mode on Ignition shows RH, dew point, WB depression, and the
   Alaska toggle inside the WEATHER group; direct mode shows none of them;
   the toggle relabels the band chips on both platforms.
3. No screen named Humidity exists; `applyHumidity` and the hand-off closure
   are deleted, not orphaned.
4. Aspect, slope, and elevation-delta chips render in Site & radio above the
   Confirm gate, bound to the same state the Ignition tab shows, with the
   shared cue.
5. Tapping Log Observation opens the capture sheet; the Obs scroll contains
   no weather steppers; capture and edit render from one observation form.
6. The freeze receipt shows dry bulb, RH + source, wind, month, obs time +
   resolved band, aspect, slope, and elevation delta, and matches what
   `logObs` freezes — byte-for-byte against the frozen obs's inputs.
7. Committing presents the frozen broadcast script with a working Copy;
   dismissing lands on the scroll with the new obs as hero.
8. The web twin logs the clock month, matching `pendingObs`.
9. All preserved accessibility identifiers behave as today;
   `PlateworksIgnitionUITests` passes with the Humidity suite removed and
   sheet-flow tests added.
10. `swift test` and `node conformance/check-web.js` pass with **zero**
    vector changes.
11. Every file path cited in this spec exists in the tree.
