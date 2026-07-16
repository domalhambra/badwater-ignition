# Badwater Ignition — GUI Workflow Restructure

| | |
|---|---|
| **Status** | Implemented — the restructure below shipped in the same PR that added this document; it now reads as the design record. |
| **Scope** | Ignition screen restructure + app-wide flow polish (status affordances, shared-state visibility, Humidity consistency) |
| **Non-goals** | No new features. No Watch-tab feature completion (shift log list, export, site gate stay M2–M6). No visual-brand changes — colors, type, and component styling stay as specified in `DESIGN.md`. |
| **Companion** | `DESIGN.md` (visual system — source of truth for tokens and components) |

Every decision below is grounded in the shipped code, cited as `file:line`
against the tree at the time of writing. Wireframes are drawn at iPhone SE
width — the worst case for the below-the-fold problem this spec fixes.

---

## 1. Sign-off list

Review is a checklist, not archaeology. The six decisions that need assent:

1. **Pinned PIG summary bar sits at the top** of the Ignition screen (not a
   bottom bar). → §4.1
2. **The bar is always visible** — it does not hide when the full result cards
   scroll into view. → §4.1
3. **Section names and annotations**: `WEATHER · IRPG TABLE A`,
   `CALENDAR · TIME · TABLES B/C/D`, `SITE · CORRECTIONS`. → §4.2
4. **StatusStrip copy and the deliberate teal→amber change** for the
   clock-override state (today it renders in brand teal). → §5
5. **Shared-weather cue copy**: `SHARED · WATCH` on Ignition,
   `SHARED · IGNITION` on Watch. → §6
6. **Implementation slicing** into three PRs. → §11

---

## 2. Problems

Four flow problems, all confirmed in source:

**P1 — Ignition is one long, undifferentiated scroll; results are below the
fold.** `IgnitionView.body` is a single flat `VStack` inside a `ScrollView`
(`App/BadwaterIgnition/Features/Ignition/IgnitionView.swift:16–61`): six chip
rows and two-to-three stepper cards stand between the screen title and the
first result. On a phone, the PIG readouts — the reason the app exists — render
off-screen. Nothing separates "weather I measured" from "calendar the table
needs" from "site corrections"; the operator holds the grouping in their head.

**P2 — Conditional rows shift the whole layout.** Switching Humidity source to
*From wet bulb* inserts an elevation-band chip row **and** a derived-RH card
mid-scroll (`IgnitionView.swift:34–39`); everything below jumps ~140 pt.
The clock-override notice appears and disappears as a whole row
(`IgnitionView.swift:45`). Watch's capture card duplicates the same jump
(`App/BadwaterIgnition/Features/Watch/WatchView.swift:155–159`), and its
freshness row swaps a trailing button in and out (`WatchView.swift:180–192`).

**P3 — Shared weather state is invisible.** Watch's capture card binds the
*same* `IgnitionModel` the Ignition tab shows (`WatchView.swift:145–159`,
by design per `WatchView.swift:12–15`). Editing dry bulb on Watch silently
changes Ignition, and vice versa. Nothing on either screen says so.

**P4 — `DESIGN.md` describes a two-tab app.** The shell ships three tabs with
Ignition as the launch tab (`App/BadwaterIgnition/App/RootView.swift:14,26–47`);
`DESIGN.md` §4 says "Two tabs" and doesn't document Watch. Fixed in the
companion `DESIGN.md` refresh, not here.

---

## 3. Carried-over principles (invariants)

This spec must not break the rules `DESIGN.md` already establishes:

- **Warm colors carry severity meaning only** — amber is caution, the
  green→red ramp is fire behavior; neither is ever decoration.
- **Interactive targets ≥ 48 pt** (`Metric.tapTarget`) for gloved hands.
- **The chain stays visible** — intermediate IRPG values (`REF FM → CORR →
  FFM`) remain on screen; "show your work" is the trust feature.
- **Instrument, not form** — no Calculate button; results update live.
- **Color is always paired with a text label** (color-vision safety).
- **Near-black dark theme** protects night vision; nothing in this spec adds
  bright chrome.

---

## 4. Spec A — Ignition restructure

### 4.1 Pinned PIG summary bar (`PIGSummaryBar`)

The headline result stays on screen at every scroll position. Inputs scroll;
the answer doesn't.

**Placement — top.** Applied as `.safeAreaInset(edge: .top, spacing: 0)` on
the existing `ScrollView` (`IgnitionView.swift:16`), inside the current
`NavigationStack`. Rationale:

- The app already has a chrome rule to inherit: **top = readouts, bottom =
  actions.** Watch pins its primary *action* at the bottom the same way
  (`WatchView.swift:41`); the tab bar already owns the bottom edge. A second
  bottom bar would stack three layers of chrome over the home indicator.
- Thumb reach argues for *interactive* elements at the bottom; the bar is
  read-only.
- Instrument framing: a gauge readout sits at the top of the panel.

**Anatomy.**

```
┌────────────────────────────────────────────┐
│  UNSH 80%      SHD 60%             EXTREME │  ≥56pt row, Surface fill
│  ▂▂▂▂▂▂▂       ▂▂▂▂▂▂                      │  3pt severity underbars
├────────────────────────────────────────────┤  1px Hairline
```

- One row, min-height 56 pt, `Surface` background, 1 px `Hairline` bottom
  border, horizontal padding `Metric.screenPadding`.
- Two mini-readouts: uppercase-mono labels `UNSH` / `SHD` (`fieldLabel()`
  idiom), numerals in `BadwaterFont.readout(26)` tinted with **each side's own
  severity color**, each readout carrying a 3 pt severity underbar — the
  horizontal echo of `ResultCard`'s 4 pt leading stripe
  (`Components.swift:143–149`).
- Right-aligned: the **unshaded** fire-behavior word (`Extreme`, `High`, …) in
  its severity color. The text label is mandatory — color never signals alone
  (invariant §3). Unshaded is the more hazardous interpretation, matching the
  precedent set by the interpretation panel (`IgnitionView.swift:170–171`).
- **Firmness echo:** each underbar goes solid when the reading is firm and warms
  into a current→neighbour gradient when that shading's plausible envelope
  crosses a fire-behavior band — the horizontal echo of the cell-edge marker
  `ResultCard` gained in the sensitivity feature (`Sensitivity.Envelope`,
  `IgnitionModel.sensitivity`). The glance thus carries the same "this one's on
  the move" cue as the cards, at zero added height.
- **Not in the bar:** FFM, the correction chain, and the amber "could read …"
  caption. The bar answers exactly one question — *how bad, both shadings* — and
  defers verification (including the firmness caption and tap-to-expand detail)
  to the chain strip and result cards below. A bar that restates everything is a
  second results section, not a summary.

**Behavior — always visible; never hides.**

- No hide-on-scroll, even when the full `ResultCard`s are in view. Detecting
  "results visible" needs iOS 18's `onScrollVisibilityChange` or a brittle
  `GeometryReader` offset dance on iOS 17; hiding is also motion (conflicts
  with the Reduce Motion posture, §8); and an instrument readout that
  disappears when you glance at it undermines trust. The duplication while the
  cards are on-screen is intentional: bar = headline, cards = verification
  detail.
- Values come from the same `model.estimate` the cards render
  (`IgnitionView.swift:157–167`) — bar and cards cannot disagree.
- Numerals are already `monospacedDigit` via `BadwaterFont.readout`, so live
  updates don't jitter the layout.

**Accessibility.**

- `.accessibilityElement(children: .ignore)` with a combined spoken value:
  *"Probability of ignition: unshaded 80 percent, shaded 60 percent.
  Extreme."*
- New identifier: `pig-summary`.
- Under large Dynamic Type the row may wrap to two lines (readouts above,
  behavior word below); layout is capped at `.accessibility2` (§8).

> **Decision:** top-pinned via `safeAreaInset`, always visible, unshaded +
> shaded PIG plus the unshaded behavior word, nothing else.

### 4.2 Grouped sections

Inputs are chunked into three labeled groups whose names and order mirror the
IRPG worksheet itself (PMS 461 pp. 44–49) — the mental model every trained
operator already carries. Each group is introduced by a `SectionHeader`
(§4.4).

| # | Section header | Contents (order within group) |
|---|---|---|
| 1 | `WEATHER` · annotation `IRPG TABLE A` | Humidity-source chips (the mode switch — first, because it decides what follows) → Dry bulb + (RH \| Wet bulb) steppers → *wet-bulb mode only:* elevation-band chips + derived-RH card, contained at the **end** of the group (§4.3) |
| 2 | `CALENDAR · TIME` · annotation `TABLES B/C/D` | Month chips (keeps the resolved-letter title, `IgnitionView.swift:94–98`) → Time-of-day chips → clock `StatusStrip` (always present, §5) |
| 3 | `SITE` · annotation `CORRECTIONS` | Aspect + Slope side-by-side → Elevation vs. weather site. These persist across launches (`IgnitionModel.persist()`); the annotation may carry a one-word `STICKY` hint — copy owner's call at implementation |
| 4 | *(results — no header change)* | Chain strip → two `ResultCard`s → interpretation → disclaimer, **order unchanged** (`IgnitionView.swift:55–58`) |

The screen header row ("Ignition" + `IRPG p.44–49`) remains the first scroll
item, under the pinned bar.

> **Decision:** three input groups — `WEATHER`, `CALENDAR · TIME`, `SITE` —
> annotated with their IRPG table letters; results section order untouched.

### 4.3 Conditional-jump fix — containment, not reservation

The wet-bulb-only controls (elevation-band chips + derived-RH card) stay
**inside the visually bounded WEATHER group, placed last in the group**. When
the mode switches, the group's own boundary grows or shrinks and everything
below it moves *as one block* — the eye tracks a single container resizing
rather than rows materializing mid-list. Transition is crossfade-only under
Reduce Motion (§8).

Rejected alternatives, one line each:

- *Reserve blank space:* wastes ~140 pt in direct-RH mode — the common case
  (Kestrel-style meters read RH directly).
- *Disabled ghost controls:* a permanently visible five-chip elevation row that
  does nothing in direct mode violates the calm-instrument ethos and invites
  taps that can't land.

This fix applies **verbatim** to Watch's capture card, which duplicates the
same conditional (`WatchView.swift:155–159`) — resolved structurally by the
shared `WeatherInputGroup` extraction (§6, §11).

> **Decision:** conditionals live at the end of their bounded group; no
> reserved space, no ghost controls.

### 4.4 New component: `SectionHeader`

```swift
SectionHeader(title: "Weather", annotation: "IRPG Table A")
// optional trailing accessory slot — used by the shared-weather cue (§6)
```

- Title in the existing `fieldLabel()` idiom (SF Mono, caption, uppercase,
  +0.6 kerning, `Muted` — `Typography.swift:39–47`); right-aligned mono
  annotation, matching the established chip-title pattern
  (`Month · C (Feb Mar Apr Oct Nov)`).
- Pure text row — not interactive, no disclosure behavior.
- Lives in `App/BadwaterIgnition/DesignSystem/Components.swift` beside the
  other four components.

### 4.5 Wireframes (iPhone SE width — worst case)

**Before (today):** first visible viewport, direct-RH mode.

```
┌──────────────────────────────────────┐
│ Ignition                IRPG P.44–49 │
│                                      │
│ HUMIDITY SOURCE                      │
│ (Direct) (From wet bulb)             │
│ ┌────────────────┐┌────────────────┐ │
│ │ DRY BULB       ││ REL. HUMIDITY  │ │
│ │ 90 °F    − / + ││ 8 %      − / + │ │
│ └────────────────┘└────────────────┘ │
│ MONTH · C (FEB MAR APR OCT NOV)      │
│ (Jan)(Feb)(Mar)(Apr)(May)(Jun)…      │
│ TIME OF DAY                          │
│ (0800-0959)(1000-1159)(1200-1359)…   │
│ ASPECT           SLOPE               │
│ (N)(E)(S)(W)     (0-30%)(31%+)       │
╞═════════ fold (iPhone SE) ═══════════╡
│ ELEVATION VS. WEATHER SITE           │
│ (Below)(Level)(Above)                │
│ REF FM → CORR → FFM                  │
│ [UNSHADED 80%]  [SHADED 60%]   ← !!! │
│ Interpretation…                      │
└──────────────────────────────────────┘
```

The PIG result — the point of the screen — is the `!!!` row below the fold.

**After:** same viewport, same mode.

```
┌──────────────────────────────────────┐
│ UNSH 80%   SHD 60%           EXTREME │ ← pinned bar
│ ▂▂▂▂▂▂▂    ▂▂▂▂▂▂▂                   │   (severity underbars)
├──────────────────────────────────────┤
│ Ignition                IRPG P.44–49 │
│                                      │
│ WEATHER · IRPG TABLE A   ⧉ SHARED·WATCH
│ ┌──────────────────────────────────┐ │
│ │ HUMIDITY SOURCE                  │ │
│ │ (Direct) (From wet bulb)         │ │
│ │ ┌──────────────┐┌──────────────┐ │ │
│ │ │ DRY BULB     ││ REL. HUMIDITY│ │ │
│ │ │ 90 °F   − /+ ││ 8 %     − /+ │ │ │
│ │ └──────────────┘└──────────────┘ │ │
│ └──────────────────────────────────┘ │
│ CALENDAR · TIME · TABLES B/C/D       │
│ (Jan)(Feb)(Mar)(Apr)(May)(Jun)…      │
╞═════════ fold (iPhone SE) ═══════════╡
│ (0800-0959)(1000-1159)(1200-1359)…   │
│ ◷ TRACKING CLOCK · JUL · 1400-1559   │ ← StatusStrip (always present)
│ SITE · CORRECTIONS                   │
│ (N)(E)(S)(W)     (0-30%)(31%+)       │
│ (Below)(Level)(Above)                │
│ REF FM → CORR → FFM                  │
│ [UNSHADED 80%]  [SHADED 60%]         │
│ Interpretation…                      │
└──────────────────────────────────────┘
```

The answer is now visible at every scroll offset; the fold only decides how
much *input detail* is on screen.

**After — wet-bulb mode variant** (the conditional, contained):

```
│ WEATHER · IRPG TABLE A   ⧉ SHARED·WATCH
│ ┌──────────────────────────────────┐ │
│ │ HUMIDITY SOURCE                  │ │
│ │ (Direct) (From wet bulb)         │ │
│ │ ┌──────────────┐┌──────────────┐ │ │
│ │ │ DRY BULB     ││ WET BULB     │ │ │
│ │ │ 90 °F   − /+ ││ 62 °F   − /+ │ │ │
│ │ └──────────────┘└──────────────┘ │ │
│ │ ELEVATION BAND · 27 INHG         │ │  ← wet-bulb-only rows,
│ │ (<2k)(2-4k)(4-6k)(6-8k)(8k+)     │ │    last inside the group
│ │ REL. HUMIDITY (from wet bulb) 14%│ │
│ └──────────────────────────────────┘ │
│ CALENDAR · TIME · TABLES B/C/D       │  ← everything below moves
│ …                                    │    as one block
```

---

## 5. Spec B — `StatusStrip`

One component replaces both jumping affordances. Principle: **annunciator
panel** — the light turns on and off; the panel never moves.

**Anatomy.** A permanently present single-line row: leading SF Symbol icon,
mono caption (`BadwaterFont.labelSmall`, matching the current freshness row,
`WatchView.swift:177–178`), optional trailing capsule button. Fixed min-height
via a new `Metric.statusStripHeight` token so **height is identical across all
states** at a given type size. Content and color change; presence never does.

**States.**

| Screen | State | Icon | Caption | Tint | Trailing / action |
|---|---|---|---|---|---|
| Ignition | Clock tracking (nominal) | `clock` | `Tracking clock · Jul · 1400-1559` | `Muted` | — |
| Ignition | Clock overridden | `clock.arrow.circlepath` | `Set manually — tap to resume clock` | `SignalAmber` | whole row tappable → `resumeAutoClock()` |
| Watch | Weather just read | `clock` | `Weather just read` | `Muted` | — |
| Watch | Fresh | `clock` | `Weather read 4 min ago` | `Muted` | — |
| Watch | Never read | `clock` | `Weather not read yet` | `Muted` | — |
| Watch | Stale | `exclamationmark.triangle.fill` | `Read 42 min ago — confirm current` | `SignalAmber` | `Mark current` capsule (≥48 pt target) → `confirmPendingWeatherCurrent()` |

- Behavior preserved exactly: the Ignition row keeps the
  `clock-override-notice` identifier and its tap → `resumeAutoClock()`
  (`IgnitionView.swift:72–84`, `IgnitionModel.swift:106`); the Watch capsule
  keeps `mark-weather-current` (`WatchView.swift:191`). New container
  identifier: `status-strip`.
- The nominal Ignition caption surfaces what the clock is currently resolving
  (month short name + time band label) — the strip earns its permanent slot by
  showing live state, not by sitting empty.
- **Deliberate color change (sign-off #4):** today the clock-override notice
  renders in brand teal (`BadwaterColor.accent`, `IgnitionView.swift:79`).
  It becomes `SignalAmber`: an override standing in for the clock is a
  *caution* ("a stale night/day rule is never silent" —
  `IgnitionView.swift:70–71`), `SignalAmber` is documented as exactly that
  ("Caution notes only", `DESIGN.md` §2), and it unifies semantics with
  Watch's stale state. Teal keeps meaning *brand/interactive*, never warning.
- **Color rule:** `Muted` nominal, `SignalAmber` caution. Severity-ramp colors
  never appear in a status strip — severity is fire behavior, not app state.

> **Decision:** one `StatusStrip` component, always present, fixed height,
> two screens, six states, amber for caution.

---

## 6. Spec C — Shared-weather cue

Labeling only — no new behavior. The `WEATHER` `SectionHeader` carries a
trailing accessory on both screens: a `link` SF Symbol + mono caption.

| Screen | Accessory |
|---|---|
| Ignition | `⧉ SHARED · WATCH` |
| Watch (capture card) | `⧉ SHARED · IGNITION` |

- Copy must fit one line alongside the section title at `.accessibility2`; if
  it collides, the accessory wraps below the title rather than truncating.
- Accessibility label: *"Weather inputs are shared with the Watch tab; edits
  apply everywhere."* (mirrored on Watch).
- Kept honest structurally: implementation extracts the duplicated weather
  controls (`IgnitionView.swift:21–39` vs `WatchView.swift:145–159`) into one
  shared `WeatherInputGroup` view used by both screens. That is organization,
  not a feature — same controls, same bindings, one source file — and it makes
  the cue self-maintaining: the two screens *can't* drift apart.

> **Decision:** a passive `SHARED · <other tab>` cue on both WEATHER headers,
> backed by a single extracted `WeatherInputGroup`.

---

## 7. Spec D — Humidity consistency notes

Humidity is already the reference pattern — result first (72 pt RH readout,
`HumidityView.swift:54–69`), then inputs. The pinned bar in §4.1 *imports*
Humidity's result-first idea into Ignition. Structure unchanged; three touch-ups:

1. **Alaska toggle target size:** the `Toggle` row
   (`HumidityView.swift:77–85`) uses `.padding(.vertical, 10)` around body
   text — verify the interactive row meets the 48 pt target; pad to
   `Metric.tapTarget` if short.
2. **Disclaimer styling** already matches Ignition's (`labelSmall`, `Muted`,
   centered) — confirm it stays aligned when Ignition's layout changes.
3. **Hand-off transparency (note only):** "Use in ignition calc" lands as
   *direct-RH* mode (`IgnitionModel.applyHumidity`,
   `IgnitionModel.swift:159`), so after the hand-off the Ignition WEATHER
   group visibly shows the mode chip on `Direct` with the pushed value — the
   flip is the confirmation. No change needed.

---

## 8. Accessibility & motion requirements

Promoted from `DESIGN.md` §7.3 "open" items to requirements of this spec:

- **Dynamic Type:** labels and body text adopt relative text styles /
  `@ScaledMetric` (today `BadwaterFont` uses fixed point sizes,
  `Typography.swift:11–26`). Numeric readouts may cap their growth; layout is
  validated up to `.accessibility2`. Implementation-note level — not a type
  redesign.
- **Reduce Motion:** every transition this spec introduces falls back to
  opacity-only — the WEATHER group resize (§4.3), StatusStrip content swaps
  (§5), and the existing severity-color cross-fade.
- **VoiceOver:** all pre-existing accessibility identifiers are preserved
  verbatim — they anchor `App/BadwaterIgnitionUITests`. New identifiers
  introduced by this spec: `pig-summary`, `status-strip`.
- **Existing a11y behaviors carried forward:** `StepperCard`'s adjustable
  action, `ChipPicker`'s selected traits, combined result elements
  (`Components.swift:29–39, 113–120, 151–154`).

---

## 9. Precedents

Practical grounding, one line each:

- **Pinned live summary:** Apple Stocks/Health pinned headers; Baymard
  Institute's sticky order-summary research; loan/mortgage calculator apps —
  the result stays visible while inputs change.
- **Apple HIG — Layout & Toolbars:** bottom bars are for *actions*, which is
  precisely why a read-only summary belongs at the top; safe-area insets are
  the sanctioned pinning mechanism.
- **Form chunking:** NN/g field-grouping guidance and Luke Wroblewski's *Web
  Form Design* — groups must match the user's mental model. Here the model is
  domain-native: the IRPG worksheet order itself (PMS 461 pp. 44–49).
- **Progressive disclosure (NN/g):** mode-switched controls disclose within
  their container instead of mutating the global layout.
- **Annunciator panel / persistent banner (Material banners, instrument
  panels):** a fixed status region whose content changes — the panel never
  moves. Matches the app's "field instrument" ethos verbatim.

---

## 10. Acceptance criteria

A future implementation PR satisfies this spec when:

1. `pig-summary` exists, renders both PIG values + the unshaded behavior word,
   and is present (hittable by UI tests) at every scroll offset of the
   Ignition screen.
2. Toggling Humidity source changes layout **only inside** the WEATHER group's
   container: the `SITE` header's y-position moves as one block; no rows
   interleave outside the group.
3. `status-strip` renders at identical height across all its states at a given
   Dynamic Type size, on both screens.
4. Tapping the clock-override state still calls `resumeAutoClock()`;
   `clock-override-notice` and `mark-weather-current` identifiers behave as
   today.
5. No severity-ramp color appears in any `StatusStrip` state; caution states
   use `SignalAmber` only.
6. All pre-existing accessibility identifiers are unchanged
   (`BadwaterIgnitionUITests` passes without identifier edits).
7. Ignition and Watch weather inputs render from the single shared
   `WeatherInputGroup`; both WEATHER headers show their `SHARED` accessory.
8. `DESIGN.md` and this spec agree on tab count, order, and launch tab.
9. Every file path cited in this spec exists in the tree.

---

## 11. Implementation appendix

**Files touched (later PRs — nothing changes in this docs-only PR):**

| File | Change |
|---|---|
| `App/BadwaterIgnition/DesignSystem/Components.swift` | add `PIGSummaryBar`, `SectionHeader`, `StatusStrip` |
| `App/BadwaterIgnition/DesignSystem/Typography.swift` | add `Metric.statusStripHeight` (+ any section-spacing token) |
| `App/BadwaterIgnition/Features/Ignition/IgnitionView.swift` | pinned bar, section grouping, StatusStrip adoption |
| `App/BadwaterIgnition/Features/Watch/WatchView.swift` | StatusStrip adoption, `WeatherInputGroup` adoption, shared cue |
| `App/BadwaterIgnition/Features/` (new file) | extracted `WeatherInputGroup` |
| `App/BadwaterIgnition/Features/Humidity/HumidityView.swift` | minor (§7) |
| `DESIGN.md` | post-implementation: rewrite §4.1 to the new structure; fold new components into §5 |

**Identifiers:** preserved — every existing one; new — `pig-summary`,
`status-strip`.

**Suggested PR slicing (sign-off #6):**

1. **PR 1 — components + Ignition:** `SectionHeader`, `StatusStrip`,
   `PIGSummaryBar`, Ignition restructure. Independently shippable; biggest
   user-visible win.
2. **PR 2 — Watch adoption + shared extraction:** `WeatherInputGroup`, Watch's
   StatusStrip + shared cue, containment fix on the capture card.
3. **PR 3 — docs:** rewrite `DESIGN.md` §4 to describe the shipped structure;
   mark this spec **Implemented** (it becomes an archival record).

**Out of scope, restated:** Watch M2–M6 features (shift-log list, export UI,
site-confirmation gate, trends), any new calculation capability, palette or
typography changes.
