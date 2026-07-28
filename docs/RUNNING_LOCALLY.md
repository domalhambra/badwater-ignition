# Running Plateworks Ignition on iOS, watchOS and a device

A first-time Xcode guide for this repo, written against a verified run on
2026-07-27 (Xcode 26.6, XcodeGen 2.x, macOS 27).

The code for the widget, Live Activity and watch app is **already written,
merged and CI-green** (PR #31). What was never done is running any of it. This
document is how you do that.

---

## The one rule that will bite you

**`PlateworksIgnition.xcodeproj` is generated, not committed.** It is built from
[`project.yml`](../project.yml) by XcodeGen, and running `xcodegen generate`
overwrites it completely.

So: **never change build settings, signing teams, capabilities or Info.plist
keys in Xcode's UI.** They look like they stick, and then the next `xcodegen
generate` silently throws them away and you spend an hour wondering why the
widget went empty. Every setting change goes in `project.yml`, then you
regenerate.

Xcode's UI is for *running and looking*, not for configuring. That is the
opposite of how most Xcode tutorials work, and it is the single most likely way
to lose a morning here.

---

## Phase 0 — first-time setup (once)

```bash
brew install xcodegen xcbeautify
```

Then, from the repo root:

```bash
xcodegen generate
```

That creates `PlateworksIgnition.xcodeproj`. Open it:

```bash
open PlateworksIgnition.xcodeproj
```

### Known issue: the simulator panel needs a sudo fix

Claude's live Simulator panel currently reports Xcode as "installed but not
selected." The fix needs your password, so run it yourself:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Nothing else in this document depends on it — `xcodebuild` and `simctl` work
regardless.

---

## Orienting yourself in Xcode

Four things matter. Ignore the rest for now.

| Where | What it is |
|---|---|
| **Toolbar, top-left: `PlateworksIgnition > iPhone 17 Pro`** | The **scheme** (what to build) and the **destination** (where to run it). You will change these constantly. Click the left half for scheme, right half for destination. |
| **▶ Play button** | Build + install + launch. `⌘R`. |
| **■ Stop button** | Kills the running app. `⌘.` |
| **Bottom pane** | The console — `print()` output and crash messages. `⌘⇧C` if it's hidden. |

The three schemes in this project:

- **PlateworksIgnition** — the phone app. Building it also builds and embeds the
  widget and the watch app.
- **PlateworksWidget** — the widget extension alone. Exists so a broken embed
  fails loudly instead of silently dropping the widget.
- **PlateworksWatch** — the watch app. Needs a *watchOS* destination; the iOS
  scheme does not compile watch content for a simulator.

---

## The second rule that will bite you

**Build signed, even for the Simulator.** Nearly every `xcodebuild` line in this
repo passes `CODE_SIGNING_ALLOWED=NO`. That is right for CI, which only needs to
compile — but it embeds **no entitlements**, which means there is no App Group
container, which means the widget and the complication read nothing and render
"No obs logged" forever. Nothing errors. It looks exactly like a data bug, and
it is the same signature as the mismatched-group-identifier trap in Task 14 of
the plan.

You do not need an Apple ID to avoid this. Ad-hoc signing is enough:

```bash
xcodebuild build -project PlateworksIgnition.xcodeproj -scheme PlateworksIgnition \
  -destination "id=$SIM" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES
```

Pressing ▶ in Xcode does the right thing already. It is the command line that
catches people out.

Check it took, before blaming the code:

```bash
xcrun simctl get_app_container "$SIM" org.plateworks.ignition group.org.plateworks.ignition
```

A path means the group container exists. A usage message means it does not, and
the record is going to Application Support via `ObservationRecordStore`'s
fallback — which `RecordReader`, by design, will not follow.

---

## Phase A — the Simulator (free, do this first)

Most of the device checklist can be run in the Simulator without an Apple
Developer account. App Group containers work in the Simulator without
provisioning — **provided the build is signed**, see the rule above — which is
what makes this possible.

### A1. Run the phone app

1. Scheme: **PlateworksIgnition**. Destination: **iPhone 17 Pro**.
2. Press **▶**.

Verified working on 2026-07-27: the app launches to the Ignition tab with the
Humidity · Ignition · Obs bar.

### A2. Add the widget to the home screen

1. With the app running, press `⌘⇧H` to go to the simulator home screen.
2. Click and **hold** on empty space until the icons jiggle.
3. Tap **Edit → Add Widget** (top-left), search "Plateworks".
4. Add the **small** one, then repeat for the **lock screen** one
   (`accessoryRectangular`) via Settings → Wallpaper → Customize → Lock Screen.

Checklist items this covers: gallery presence in both families, "No obs logged"
on a fresh shift, dark mode, accessibility text sizes (Settings → Accessibility
→ Display & Text Size → Larger Text).

### A3. Watch the widget update

Log an observation in the app and confirm the widget picks it up within seconds.
Then wait out the cadence and confirm it flips to the overdue presentation and
**shows no PIG** — that last part is the display-policy guardrail in
[`CLAUDE.md`](../CLAUDE.md), and it is the single most important thing on the
whole checklist.

### A4. Live Activity

Live Activities run in the Simulator on iPhone 15 Pro and later. Log the first
obs of a shift and confirm a countdown appears on the lock screen (`⌘L`) and in
the Dynamic Island.

Then the ones that actually catch bugs:

- Log a **second** obs — the countdown should *move*, not stack a second one.
- Force-quit and relaunch — there should be **exactly one** activity.
- Start a new shift — it should **end**.

### A5. The watch app

No watch simulator is paired yet. Create the pair once:

```bash
xcrun simctl pair "$(xcrun simctl list devices available | grep -m1 'Apple Watch Series 11 (46mm)' | grep -oE '[0-9A-F-]{36}')" \
                  "$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro' | grep -oE '[0-9A-F-]{36}')"
```

Or in Xcode: **Window → Devices and Simulators → Simulators**, select the
iPhone, set **Paired Watch**.

Then set the scheme to **PlateworksWatch**, destination to the paired watch, and
press ▶. Confirm the glance screen shows the last snapshot rather than blank,
and that the complication updates on the face.

**Simulator caveat:** `WatchConnectivity` between paired simulators is real but
flaky, and it is not evidence about background delivery with the phone locked.
That specific check stays on the device list.

---

## Phase B — a real device

### B1. You need a paid Apple Developer Program membership

This is the blocker nobody wrote down, and it costs **$99/year**.

A free Apple ID ("personal team") can install an app on your own iPhone, but it
**cannot provision App Groups**. This whole architecture — widget, complication —
reads the observation record out of an App Group container. Without it, every
glanceable surface is permanently empty, and *nothing errors*. It reads exactly
like a data bug.

You need it for the App Store release anyway, so pay for it before spending any
time debugging empty widgets.

Sign up at [developer.apple.com/programs](https://developer.apple.com/programs/).
Then in Xcode: **Settings → Accounts → +** and sign in.

> Right now this Mac has **zero code-signing identities** — no Apple ID is
> configured in Xcode at all. That is expected, not broken.

### B2. Register both App Groups

In the [Developer portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup),
create **both**:

- `group.org.plateworks.ignition` — phone app + widget
- `group.org.plateworks.ignition.watch` — watch app + complication

Two groups, not one, because the complication is a separate process from the
watch app and an App Group does not reach across from the phone to the watch.

### B3. Set your team in `project.yml` — not in Xcode

Find `DEVELOPMENT_TEAM: ""` in [`project.yml`](../project.yml) and put your
10-character Team ID in it (Developer portal → Membership).

```yaml
DEVELOPMENT_TEAM: "ABCDE12345"
```

Then `xcodegen generate` again. **Do not** set the team in Xcode's Signing &
Capabilities tab — see the rule at the top.

### B4. Run on the iPhone

1. Plug the iPhone in, unlock it, tap **Trust**.
2. On the phone: Settings → Privacy & Security → **Developer Mode** → on
   (it reboots).
3. In Xcode, pick your iPhone as the destination and press ▶.
4. First run only: Settings → General → VPN & Device Management → trust your
   developer certificate.

### B5. Work the device checklist

The remaining items in
[`PLAN_WIDGET_AND_WATCH.md`](PLAN_WIDGET_AND_WATCH.md) that only a device can
answer:

- Legibility **in sunlight** — the reason this app exists.
- Snapshot delivery with the phone **locked and the app backgrounded**.
- A late-delivered snapshot rendering by the *watch's* clock, not as fresh.
- Complication refresh cadence on a real face.
- A real multi-day record migrating through `ObservationRecordStore` intact.

Tick them off in the plan document as they pass.

---

## Verifying you haven't broken anything

Before and after any change:

```bash
swift test && swift run plateworks-vectors --check conformance/vectors.json && node conformance/check-web.js
```

Green baseline as of 2026-07-27: **140 tests, vectors up to date, 1172 parity
checks, 0 mismatches.**

---

## Already resolved (2026-07-27)

Two checklist items were settled locally and need no device:

- ✅ **`NSSupportsLiveActivities` reaches the built `Info.plist`.** Verified
  present (`true`) in the built simulator bundle, not just in `project.yml`.
  This was flagged as the likeliest silent failure; it is not one.
- ✅ **Widget and watch app are actually embedded** — `PlugIns/PlateworksWidget.appex`
  and `Watch/PlateworksWatch.app` are both present in the built bundle.

## Resolved drift: CI now matches your Xcode

CI used to run `macos-15` while this Mac runs **Xcode 26.6**, and the newer
compiler rejected code CI accepted — `Activity<ObsActivityAttributes>` is not
`Sendable` in the iOS 26 SDK, so sending it into a `Task` from `@MainActor` is
an error, and `ObsActivityController.swift` failed to build with three of them.

Fixed at the time with `@preconcurrency import ActivityKit`. Still worth
revisiting: that suppresses concurrency diagnostics for the whole file, where a
narrow `@unchecked Sendable` wrapper around the one call site would be tighter.

**CI is pinned to `macos-26` as of 2026-07-27**, so green CI and a green local
build now mean the same thing. If you move the local toolchain forward, move the
pin with it — the general point outlived the specific error: *CI green does not
mean it builds on your Mac* unless the two are on the same Xcode.
