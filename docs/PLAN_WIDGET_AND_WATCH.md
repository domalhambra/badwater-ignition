# Widget & watchOS Implementation Plan (plan items 3.4, 3.5)

**Goal:** Put the latest logged observation where a crew can see it without
unlocking a phone — a home/lock-screen widget, a Dynamic Island countdown, and a
watch app with a complication.

**Architecture:** Both surfaces are **read-only mirrors of the frozen record**.
The widget reads the App Group container directly through a reader that cannot
write; the watch receives a small snapshot over `WCSession`. The one
safety-relevant rule — *when to stop showing a number* — lives in `BadwaterCore`
as a pure function so it is golden-tested on Linux CI, not in a widget extension
nobody can test.

**Tech stack:** SwiftUI · WidgetKit · ActivityKit · WatchConnectivity ·
XcodeGen · Swift 6 language mode.

---

## Progress

| Task | State |
|---|---|
| 1. `ObsGlance` in `BadwaterCore` | **Done** — 13 tests, on `main` |
| 2. `RecordLocation` | Not started |
| 3. Widget target | Not started |
| 4. Timeline provider | Not started |
| 5. Widget views | Not started |
| 6. Reload on record mutation | Not started |
| 7. Live Activity attributes | Not started |
| 8. Live Activity presentation + lifecycle | Not started |
| 9. `WatchSnapshot` | Not started |
| 10–13. watchOS app + complication | Not started |
| 14. Bundle-id / entitlement audit | Not started |
| 15. CI covers the new targets | Not started — **do this with Task 3** |

**Everything from Task 2 onward needs a Mac.** Task 1 was pure core and was done
in a cloud session; every remaining task touches an Xcode target, an entitlement,
or a device-only behaviour.

### Starting a fresh session

Paste this:

> Continue `docs/PLAN_WIDGET_AND_WATCH.md` in `domalhambra/badwater-ignition`,
> starting at Task 2. Task 1 (`ObsGlance`) is done and merged. Read
> `CLAUDE.md` first — the **display policy** guardrail governs every surface in
> this plan. Work on branch `claude/firefighting-weather-calculator-refactor-mmkxgy`
> off the latest `main`. Verify with `swift test`,
> `swift run badwater-vectors --check conformance/vectors.json`,
> `node conformance/check-web.js`, and `xcodegen generate && xcodebuild build`.
> Wire CI for each new target as you create it (Task 15), not at the end.

Requirements for that session: macOS with Xcode 16+, `xcodegen`, `xcbeautify`, a
Swift 6 toolchain, and Node. A physical device (and a paired watch, for 3.5) for
the verification checklist at the end of this document.

---

## The display policy these are built on

Settled by design review before planning. It governs every surface added here and
every one added later.

> **Persistent, glanceable surfaces show only frozen observations.**
> A widget, a lock-screen notification, a Live Activity, or a complication may
> show a **logged** observation's PIG — always with its time and age — and must
> stop showing the number once the observation is superseded. The **live
> estimate** never appears on a persistent surface.
>
> **Transient, explicitly-requested read-outs may report the live estimate**,
> because the operator asked half a second ago and hears the IRPG caveat in the
> same breath. This is why `CurrentIgnitionIntent` speaking the live PIG is
> legitimate and a widget showing it would not be.
>
> **Freezing a reading requires the capture card.** No surface outside the app
> may create an observation. This is why the log intent opens the app, and why
> the watch app is read-only.

Two things follow that are easy to get wrong later:

1. The line is **not** "computed values never leave the app" — the radio
   broadcast script, the IMET `.xlsx`, and the NWS spot request have always
   carried PIG outside the app, and they are correct to. The line is *volatile vs
   frozen*, and *persistent vs transient*.
2. Past the staleness threshold the widget does not show a dimmed or caveated
   number. It **changes job** and becomes the cadence annunciator. A crew glancing
   at a wrist wants "obs overdue 40 min", not a number they have to date-check.

---

## Sequencing

```
Task 1  ObsGlance in BadwaterCore ──┬──► Tasks 2-6  widget (3.4)
                                    ├──► Task 7-8   Live Activity (3.4b)
Task 9  WatchSnapshot in core ──────┴──► Tasks 10-14 watchOS (3.5)
Task 15 CI covers the new targets  (do NOT leave until last — see note)
```

Task 15 is listed last but should be done **as soon as the first new target
exists**. The `canImport(AppKit)` branches in `WatchView` rotted for months
precisely because nothing compiled them; a widget extension will do the same.

---

## File map

| File | Responsibility |
|---|---|
| `Sources/BadwaterCore/WeatherWatch/ObsGlance.swift` | **New.** Pure staleness decision: given the latest obs and `now`, is this a readable reading or an overdue annunciation, and when does that change? |
| `Tests/BadwaterCoreTests/ObsGlanceTests.swift` | **New.** Golden tests for the above, on Linux CI. |
| `Sources/BadwaterCore/WeatherWatch/WatchSnapshot.swift` | **New.** Small `Codable` payload the phone sends the watch. |
| `Tests/BadwaterCoreTests/WatchSnapshotTests.swift` | **New.** Round-trip + projection tests. |
| `App/Shared/RecordLocation.swift` | **New.** App Group identifier, filenames, container URL. Shared by app + widget targets. |
| `App/BadwaterIgnition/Features/Watch/ObservationRecordStore.swift` | **Modify.** Use `RecordLocation` instead of its own private copies. |
| `App/BadwaterWidget/RecordReader.swift` | **New.** Read-only access to the record. No writes, no migration. |
| `App/BadwaterWidget/LatestObsProvider.swift` | **New.** `TimelineProvider` — two entries, no polling. |
| `App/BadwaterWidget/LatestObsWidgetViews.swift` | **New.** `systemSmall` + `accessoryRectangular` renderings. |
| `App/BadwaterWidget/BadwaterWidgetBundle.swift` | **New.** `@main` bundle. |
| `App/Shared/ObsActivityAttributes.swift` | **New.** `ActivityAttributes` shared by app (starts) and widget (renders). |
| `App/BadwaterWidget/ObsCountdownLiveActivity.swift` | **New.** Lock screen + Dynamic Island presentations. |
| `App/BadwaterIgnition/Features/Watch/ObsActivityController.swift` | **New.** Start/update/end the Live Activity. |
| `App/BadwaterIgnition/Features/Watch/WatchSessionSender.swift` | **New.** `WCSession` on the phone side. |
| `App/BadwaterWatch/BadwaterWatchApp.swift` | **New.** watchOS app entry point. |
| `App/BadwaterWatch/WatchSessionReceiver.swift` | **New.** `WCSession` on the watch side. |
| `App/BadwaterWatch/WatchGlanceView.swift` | **New.** The single watch screen. |
| `App/BadwaterWatchWidget/` | **New.** Complication (`accessoryCircular`, `accessoryCorner`, `accessoryInline`). |
| `project.yml` | **Modify.** Three new targets, entitlements, `NSSupportsLiveActivities`. |
| `.github/workflows/ci.yml` | **Modify.** Build the new targets. |

---

## Task 1: `ObsGlance` — the staleness decision, in the core  ✅ DONE

> **Landed.** 13 tests in `Tests/BadwaterCoreTests/ObsGlanceTests.swift`; full
> core suite 111 tests green, vectors byte-identical, 1172 parity checks green.
> Two edges were pinned beyond the plan as written: an observation stamped ahead
> of `now` (back-fill or clock adjustment) floors its age at zero instead of
> rendering negative, and a test asserts that a timeline entry scheduled at
> `nextTransition` actually lands on `.overdue` rather than one second short.
> `at(_:latest:cadence:)` takes the display moment explicitly so a watch can pass
> its own clock and never present a late delivery as fresh.
>
> `ObsGlance.standardCadence` also landed here, so Task 4's note about moving the
> cadence constant into the core is already satisfied — Task 4 only needs to
> point `ObsCadenceScheduler.cadence` at it.

The rest of this section is kept as the record of what was specified.

The widget's only safety-relevant logic. It goes in `BadwaterCore` so it is
tested on Linux CI rather than living untested in an extension.

**Files:**
- Create: `Sources/BadwaterCore/WeatherWatch/ObsGlance.swift`
- Test: `Tests/BadwaterCoreTests/ObsGlanceTests.swift`

### Step 1: Write the failing test

```swift
import XCTest
@testable import BadwaterCore

final class ObsGlanceTests: XCTestCase {

    private let cadence: TimeInterval = 3600
    private let observedAt = Date(timeIntervalSince1970: 1_780_000_000)

    private func obs(at date: Date) -> WeatherObs {
        let input = IgnitionInput(dryBulbF: 90, relativeHumidity: 8, month: 7,
                                  timeOfDay: .band1400_1559, aspect: .south,
                                  slope: .gentle, elevationDelta: .level)
        return WeatherObs(timestamp: date,
                          estimate: IgnitionCalculator.estimate(input),
                          rhSource: .direct)
    }

    func testNoObservationYet() {
        XCTAssertEqual(ObsGlance.at(observedAt, latest: nil, cadence: cadence), .none)
    }

    func testFreshObservationIsReadable() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(600),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .reading(let r) = g else { return XCTFail("expected .reading, got \(g)") }
        XCTAssertEqual(r.observedAt, observedAt)
        XCTAssertEqual(r.ageSeconds, 600, accuracy: 0.001)
        XCTAssertGreaterThan(r.pigUnshaded, 0)
    }

    /// The moment the next obs is due, the displayed one is superseded and the
    /// glance stops showing a number.
    func testAtExactlyOneCadenceItBecomesOverdue() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(cadence),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .overdue(let o) = g else { return XCTFail("expected .overdue, got \(g)") }
        XCTAssertEqual(o.observedAt, observedAt)
        XCTAssertEqual(o.overdueBySeconds, 0, accuracy: 0.001)
    }

    func testWellPastCadenceReportsHowOverdue() {
        let g = ObsGlance.at(observedAt.addingTimeInterval(cadence + 2400),
                             latest: obs(at: observedAt), cadence: cadence)
        guard case .overdue(let o) = g else { return XCTFail("expected .overdue") }
        XCTAssertEqual(o.overdueBySeconds, 2400, accuracy: 0.001)
    }

    /// A back-filled or clock-skewed observation timestamped in the future must
    /// not read as "aged negative seconds".
    func testFutureObservationClampsAgeToZero() {
        let g = ObsGlance.at(observedAt,
                             latest: obs(at: observedAt.addingTimeInterval(300)),
                             cadence: cadence)
        guard case .reading(let r) = g else { return XCTFail("expected .reading") }
        XCTAssertEqual(r.ageSeconds, 0, accuracy: 0.001)
    }

    /// The timeline's second entry: exactly when the glance flips.
    func testNextTransitionIsTheDueMoment() {
        let t = ObsGlance.nextTransition(after: observedAt,
                                         latest: obs(at: observedAt), cadence: cadence)
        XCTAssertEqual(t, observedAt.addingTimeInterval(cadence))
    }

    func testNoTransitionOnceAlreadyOverdue() {
        XCTAssertNil(ObsGlance.nextTransition(after: observedAt.addingTimeInterval(cadence + 60),
                                              latest: obs(at: observedAt), cadence: cadence))
    }

    func testNoTransitionWithoutAnObservation() {
        XCTAssertNil(ObsGlance.nextTransition(after: observedAt, latest: nil, cadence: cadence))
    }
}
```

### Step 2: Run to verify it fails

```sh
swift test --filter ObsGlanceTests
```
Expected: FAIL — `cannot find 'ObsGlance' in scope`.

### Step 3: Implement

```swift
import Foundation

/// What a **persistent, glanceable surface** should display for the shift's
/// latest observation — a widget, a complication, a Live Activity.
///
/// This is the single safety-relevant rule those surfaces enforce, so it lives
/// here in the pure core and is golden-tested on Linux CI rather than inside a
/// widget extension where nothing would exercise it.
///
/// ### The rule
/// A persistent surface may show a **frozen, logged** observation's PIG, with its
/// time and age. Once the *next* observation is due, the displayed one is
/// superseded — and at that point the surface does not dim or caveat the number,
/// it **changes job** and annunciates the cadence instead. A crew glancing at a
/// wrist wants "obs overdue 40 min", not a number they then have to date-check.
///
/// The live estimate never reaches these surfaces at all; see
/// `docs/PLAN_WIDGET_AND_WATCH.md` for the full display policy.
public enum ObsGlance: Equatable, Sendable {

    /// A frozen observation, fresh enough to show.
    public struct Reading: Equatable, Sendable {
        public let pigUnshaded: Int
        public let pigShaded: Int
        public let behavior: FireBehavior
        public let observedAt: Date
        /// Seconds since the observation, never negative.
        public let ageSeconds: TimeInterval

        public init(pigUnshaded: Int, pigShaded: Int, behavior: FireBehavior,
                    observedAt: Date, ageSeconds: TimeInterval) {
            self.pigUnshaded = pigUnshaded
            self.pigShaded = pigShaded
            self.behavior = behavior
            self.observedAt = observedAt
            self.ageSeconds = ageSeconds
        }
    }

    /// The displayed observation is superseded; annunciate the cadence.
    public struct Overdue: Equatable, Sendable {
        public let observedAt: Date
        /// Seconds past the moment the next observation became due.
        public let overdueBySeconds: TimeInterval

        public init(observedAt: Date, overdueBySeconds: TimeInterval) {
            self.observedAt = observedAt
            self.overdueBySeconds = overdueBySeconds
        }
    }

    /// No observation logged yet this shift.
    case none
    case reading(Reading)
    case overdue(Overdue)

    /// Decide what to show at `now`.
    ///
    /// - Parameters:
    ///   - now: the display moment.
    ///   - latest: the shift's chronologically latest observation.
    ///   - cadence: the weather-watch interval; the threshold *is* the cadence,
    ///     because a superseded observation is exactly one that the next one was
    ///     due to replace. Not a separately-tuned number.
    public static func at(_ now: Date, latest: WeatherObs?, cadence: TimeInterval) -> ObsGlance {
        guard let latest else { return .none }
        let elapsed = now.timeIntervalSince(latest.timestamp)
        if elapsed >= cadence {
            return .overdue(Overdue(observedAt: latest.timestamp,
                                    overdueBySeconds: elapsed - cadence))
        }
        return .reading(Reading(
            pigUnshaded: latest.estimate.unshaded.probabilityOfIgnition,
            pigShaded: latest.estimate.shaded.probabilityOfIgnition,
            behavior: latest.estimate.unshaded.interpretation,
            observedAt: latest.timestamp,
            // A back-filled or clock-skewed obs can be stamped ahead of `now`;
            // "aged −5 minutes" is not a thing to render.
            ageSeconds: max(0, elapsed)))
    }

    /// The next moment the glance changes — the widget timeline's second entry.
    /// `nil` when nothing further will change on its own.
    public static func nextTransition(after now: Date, latest: WeatherObs?,
                                      cadence: TimeInterval) -> Date? {
        guard let latest else { return nil }
        let due = latest.timestamp.addingTimeInterval(cadence)
        return due > now ? due : nil
    }
}
```

### Step 4: Run to verify it passes

```sh
swift test --filter ObsGlanceTests
```
Expected: PASS, 8 tests.

Then confirm nothing else moved:
```sh
swift test && swift run badwater-vectors --check conformance/vectors.json
```
Expected: all tests pass; `vectors up to date`. (`ObsGlance` is new API and is not
emitted into vectors, so the parity harness is unaffected.)

### Step 5: Commit

```sh
git add Sources/BadwaterCore/WeatherWatch/ObsGlance.swift \
        Tests/BadwaterCoreTests/ObsGlanceTests.swift
git commit -m "core: ObsGlance — the staleness rule for glanceable surfaces

The one safety-relevant decision a widget or complication makes is when to
stop showing a number. Putting it in the core means it is golden-tested on
Linux CI instead of living untested in a widget extension.

Threshold is the obs cadence itself, not a new tuned constant: a superseded
observation is exactly one the next was due to replace. Past it the glance
does not dim the PIG, it changes job and annunciates the cadence."
```

---

## Task 2: `RecordLocation` — one definition of where the record lives

**Files:**
- Create: `App/Shared/RecordLocation.swift`
- Modify: `App/BadwaterIgnition/Features/Watch/ObservationRecordStore.swift`

### Step 1: Create the shared location type

```swift
import Foundation

/// Where the observation record lives on disk.
///
/// Extracted so the app target and the widget extension cannot disagree about
/// it. They are separate processes reading the same App Group container, and a
/// drifted filename would present as "the widget is always empty" rather than as
/// an error.
enum RecordLocation {

    /// Must match the App Group entitlement on every target that reads the record.
    static let appGroupIdentifier = "group.com.badwater.ignition"

    static let shiftFilename = "shift.json"
    static let historyFilename = "history.json"

    /// The App Group container, or `nil` when the entitlement isn't provisioned.
    ///
    /// The app falls back to Application Support in that case (see
    /// `ObservationRecordStore`); the **widget deliberately does not** — an
    /// extension has no business inventing a location, and an empty widget is a
    /// better failure than one reading a file the app never writes.
    static func groupContainer() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Record", isDirectory: true)
    }
}
```

### Step 2: Point `ObservationRecordStore` at it

Replace its private `appGroupIdentifier` and `Filename` enum with references to
`RecordLocation`, keeping the Application Support fallback and the
`-uiTestingResetState` branch exactly as they are.

### Step 3: Verify the app tests still pass

```sh
xcodebuild test -project BadwaterIgnition.xcodeproj -scheme BadwaterIgnition \
  -destination "id=$SIM" -only-testing:BadwaterIgnitionTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | xcbeautify
```
Expected: PASS, including the nine `ObservationRecordStoreTests`.

### Step 4: Commit

```sh
git add App/Shared/RecordLocation.swift \
        App/BadwaterIgnition/Features/Watch/ObservationRecordStore.swift
git commit -m "Extract RecordLocation so app and widget can't disagree on the path"
```

---

## Task 3: The widget target

**Files:**
- Create: `App/BadwaterWidget/BadwaterWidgetBundle.swift`, `RecordReader.swift`
- Modify: `project.yml`

### Step 1: Read-only reader

```swift
import Foundation
import BadwaterCore

/// Read-only access to the observation record, for the widget extension.
///
/// Deliberately **not** `ObservationRecordStore`: that type migrates and writes,
/// and a widget must do neither. Read-only here is a property of the type, not a
/// convention someone has to remember — there is no code path from a widget to a
/// mutated record.
struct RecordReader {

    /// The shift's chronologically latest observation, or `nil` if there is no
    /// record, no entitlement, or nothing logged.
    static func latestObservation() -> WeatherObs? {
        guard let container = RecordLocation.groupContainer() else { return nil }
        let url = container.appendingPathComponent(RecordLocation.shiftFilename)
        guard let data = try? Data(contentsOf: url),
              let shift = try? JSONDecoder().decode(Shift.self, from: data) else { return nil }
        return shift.latest
    }
}
```

### Step 2: Widget bundle

```swift
import WidgetKit
import SwiftUI

@main
struct BadwaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestObsWidget()
        ObsCountdownLiveActivity()
    }
}
```

### Step 3: Add the target to `project.yml`

```yaml
  BadwaterWidget:
    type: app-extension
    supportedDestinations: [iOS]
    sources:
      - path: App/BadwaterWidget
      - path: App/Shared
    dependencies:
      - package: BadwaterCore
        product: BadwaterCore
    entitlements:
      path: App/BadwaterWidget/BadwaterWidget.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.badwater.ignition
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.badwater.ignition.widget
        SWIFT_VERSION: "6.0"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: Badwater Ignition
        INFOPLIST_KEY_NSExtensionPointIdentifier: com.apple.widgetkit-extension
        SKIP_INSTALL: YES
```

Add to the app target's `dependencies:`:
```yaml
      - target: BadwaterWidget
        embed: true
```
And add `App/Shared` to the app target's `sources:`.

> **Verify on a Mac:** XcodeGen's exact spelling for embedding an app extension
> has changed across versions. If `embed: true` doesn't produce an embedded
> extension, check `xcodegen --version` against the project spec docs.

### Step 4: Generate and build

```sh
xcodegen generate
xcodebuild build -project BadwaterIgnition.xcodeproj -scheme BadwaterIgnition \
  -destination "id=$SIM" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | xcbeautify
```
Expected: builds, including `BadwaterWidget`.

### Step 5: Commit

---

## Task 4: Timeline provider — two entries, no polling

**Files:** Create `App/BadwaterWidget/LatestObsProvider.swift`

```swift
import WidgetKit
import BadwaterCore

struct LatestObsEntry: TimelineEntry {
    let date: Date
    let glance: ObsGlance
}

/// Two entries and done.
///
/// The glance changes at exactly one predictable moment — when the next
/// observation becomes due — so the timeline is "now" plus "then", and the app
/// calls `WidgetCenter.shared.reloadAllTimelines()` whenever it logs, edits or
/// deletes. No periodic refresh, so this costs no background wakeups: relevant
/// on a 16-hour shift with no way to charge.
struct LatestObsProvider: TimelineProvider {

    func placeholder(in context: Context) -> LatestObsEntry {
        LatestObsEntry(date: Date(), glance: .none)
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestObsEntry) -> Void) {
        let now = Date()
        completion(LatestObsEntry(
            date: now,
            glance: ObsGlance.at(now, latest: RecordReader.latestObservation(),
                                 cadence: ObsCadenceScheduler.cadence)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestObsEntry>) -> Void) {
        let now = Date()
        let latest = RecordReader.latestObservation()
        let cadence = ObsCadenceScheduler.cadence

        var entries = [LatestObsEntry(date: now,
                                      glance: ObsGlance.at(now, latest: latest, cadence: cadence))]
        if let flip = ObsGlance.nextTransition(after: now, latest: latest, cadence: cadence) {
            entries.append(LatestObsEntry(
                date: flip,
                glance: ObsGlance.at(flip, latest: latest, cadence: cadence)))
        }
        // .never: nothing else changes on its own, and the app reloads us on any
        // record mutation.
        completion(Timeline(entries: entries, policy: .never))
    }
}
```

> **Resolved in Task 1.** `ObsGlance.standardCadence` is now the shared constant
> in `BadwaterCore`. This task only needs to change `ObsCadenceScheduler.cadence`
> to `ObsGlance.standardCadence` so the scheduler, the on-screen countdown and
> every glanceable surface cannot drift apart. The provider code above already
> references `ObsCadenceScheduler.cadence`; either spelling works once they are
> the same value, but prefer `ObsGlance.standardCadence` in the extension so the
> widget doesn't depend on an app-target type.

Then, in `WatchView`, add `WidgetCenter.shared.reloadAllTimelines()` next to each
existing `rescheduleCadence()` call so the widget follows log, edit, delete, undo
and new-shift.

---

## Task 5: Widget views

**Files:** Create `App/BadwaterWidget/LatestObsWidgetViews.swift`

Two families only: `systemSmall` (home screen) and `accessoryRectangular` (lock
screen — where this is actually read without unlocking a phone in gloves).

Requirements the renderings must meet, all of which follow from the display
policy:

- The observation **time** is as prominent as the number. A PIG without its time
  is the failure this whole design is avoiding.
- The **age** is always visible in words ("12 min ago"), never inferred.
- In `.overdue`, **no PIG is rendered at all** — the view shows the overdue
  interval and the time of the last observation.
- In `.none`, "No obs logged" and nothing else.
- Severity colour comes from `behavior.color`, the same ramp as the app; the warm
  ramp still means danger, never decoration.
- `.containerBackground(.fill.tertiary, for: .widget)` — required since iOS 17 or
  the widget renders with no background on the home screen.

### Verification

Widget rendering can't be asserted in CI. Verify by:
1. Building (CI covers this).
2. On a device or simulator: add the widget, log an observation, confirm it
   appears within a few seconds; then set the device clock forward past the
   cadence and confirm it flips to the overdue presentation.

---

## Task 6: Reload on record mutation

**Files:** Modify `App/BadwaterIgnition/Features/Watch/WatchView.swift`

Wherever `rescheduleCadence()` is called, also reload widget timelines. Wrap in
`#if canImport(WidgetKit)`.

Commit both together — the widget is stale-by-design without this.

---

## Task 7: Live Activity attributes

**Files:** Create `App/Shared/ObsActivityAttributes.swift`

```swift
import Foundation
import ActivityKit

/// The obs-cadence countdown shown on the lock screen and in the Dynamic Island.
///
/// Carries **no computed value** — not a PIG, not an FFM. This is a persistent
/// surface, and a Live Activity outlives the reading that produced it by
/// definition: it exists precisely to count down to the reading's replacement.
/// It shows when the last observation was taken and when the next is due.
struct ObsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the observation this countdown follows was taken.
        var observedAt: Date
        /// When the next observation is due — drives a `Text(timerInterval:)`.
        var dueAt: Date
    }

    /// Division or location label, fixed for the activity's life.
    var siteLabel: String
}
```

---

## Task 8: Live Activity presentation + lifecycle

**Files:**
- Create `App/BadwaterWidget/ObsCountdownLiveActivity.swift` (rendering)
- Create `App/BadwaterIgnition/Features/Watch/ObsActivityController.swift` (lifecycle)
- Modify `project.yml`: add `INFOPLIST_KEY_NSSupportsLiveActivities: YES` to the app target

**Lifecycle rules — the part that goes wrong if unstated:**

| Event | Action |
|---|---|
| First obs of a shift logged | `Activity.request` |
| Subsequent obs logged / edited | `activity.update` with the new `observedAt`/`dueAt` |
| Last obs deleted (shift empty) | `activity.end(dismissalPolicy: .immediate)` |
| New shift started | `activity.end(.immediate)` |
| App relaunched | Adopt any existing activity from `Activity<ObsActivityAttributes>.activities` rather than starting a second one |

That last row is the one that bites: without it, relaunching leaves an orphaned
activity and starts another, and the crew sees two countdowns disagreeing.

Use `Text(timerInterval:countsDown:)` for the countdown so the system updates it
without waking the app.

**Verification:** device only. Log an obs, confirm the Live Activity appears and
counts down; force-quit and relaunch, confirm exactly one activity; start a new
shift, confirm it ends.

---

## Task 9: `WatchSnapshot` — the sync payload

**Files:**
- Create: `Sources/BadwaterCore/WeatherWatch/WatchSnapshot.swift`
- Test: `Tests/BadwaterCoreTests/WatchSnapshotTests.swift`

```swift
import Foundation

/// The whole of what the phone tells the watch.
///
/// Small on purpose. The watch mirrors the *latest* reading and the cadence; it
/// has no use for history, and `WCSession.updateApplicationContext` is far more
/// reliable with a small dictionary. Being a value type in the core means its
/// encoding is golden-tested on Linux CI like everything else here.
///
/// Carries no live estimate — see the display policy. A watch face is the most
/// persistent glanceable surface there is.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public let pigUnshaded: Int
    public let pigShaded: Int
    public let behaviorRawValue: Int
    public let observedAt: Date
    public let dueAt: Date
    /// Division / location, for context on the watch screen.
    public let siteLabel: String?

    public init(pigUnshaded: Int, pigShaded: Int, behaviorRawValue: Int,
                observedAt: Date, dueAt: Date, siteLabel: String?) { ... }

    public var behavior: FireBehavior { FireBehavior(rawValue: behaviorRawValue) ?? .veryLow }

    /// Project the latest observation into a snapshot, or `nil` when there is
    /// nothing to mirror.
    public static func from(latest: WeatherObs?, cadence: TimeInterval,
                            siteLabel: String?) -> WatchSnapshot? { ... }

    /// Re-derive the glance on the watch, so the watch applies the *same*
    /// staleness rule as the widget rather than trusting a value the phone sent
    /// minutes ago.
    public func glance(at now: Date, cadence: TimeInterval) -> ObsGlance { ... }
}
```

**Tests to write:** round-trip `Codable`; `from(latest:)` returns `nil` for an
empty shift; the projected `dueAt` is `observedAt + cadence`; `glance(at:)` flips
to `.overdue` at the due moment **using the watch's own clock**, so a snapshot
delivered late still presents correctly.

That last test is the important one: application context is delivered
*opportunistically*, so the watch may receive a snapshot long after it was sent.
It must never render "fresh" on the strength of a stale delivery.

---

## Tasks 10–13: watchOS app

**10. Phone side** — `WatchSessionSender`: activate `WCSession`, and on every
record mutation call `updateApplicationContext` with the encoded snapshot.
`updateApplicationContext` *replaces* rather than queues, which is exactly the
semantics wanted; `transferUserInfo` would deliver every intermediate obs and
`sendMessage` needs live reachability.

**11. Watch side** — `WatchSessionReceiver`: `@Observable`, `@MainActor`,
decodes the snapshot into published state, persists the last one to disk so the
app opens showing something rather than blank.

**12. Watch UI** — one screen: PIG unshaded/shaded, band, obs time, age; or the
overdue annunciation. Renders from `snapshot.glance(at: Date(), cadence:)`, not
from the raw snapshot.

**13. Complication** — a second WidgetKit target for watchOS:
`accessoryCircular`, `accessoryCorner`, `accessoryInline`. Same glance rule. This
is the highest-value surface in 3.5.

**`project.yml` targets:** `BadwaterWatch` (`type: application`,
`supportedDestinations: [watchOS]`, `WKCompanionAppBundleIdentifier` =
`com.badwater.ignition`) and `BadwaterWatchWidget` (`type: app-extension`,
watchOS). The watch app is embedded in the iOS app.

> **Verify on a Mac:** watchOS target generation is the least-standard part of
> this plan. Confirm against the XcodeGen version in use before assuming the
> spec above is complete.

---

## Task 14: Bundle-identifier and entitlement audit

Before any device run, confirm:

- App: `com.badwater.ignition`
- Widget: `com.badwater.ignition.widget`
- Watch app: `com.badwater.ignition.watchkitapp`
- Watch complication: `com.badwater.ignition.watchkitapp.widget`
- App Group `group.com.badwater.ignition` on the app **and** the widget (not the
  watch — it can't reach it)

A mismatched group identifier presents as "the widget is always empty", which is
easy to misread as a data bug. Check this first when the widget shows nothing.

---

## Task 15: CI covers the new targets

**Do this as soon as the first new target exists, not at the end.**

**Files:** Modify `.github/workflows/ci.yml`

Add to the `app-build` job, after the existing iOS build:

```yaml
      - name: Build (widget extension)
        run: |
          set -euo pipefail
          xcodebuild build -project BadwaterIgnition.xcodeproj \
            -scheme BadwaterIgnition -destination "id=${{ steps.sim.outputs.udid }}" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | xcbeautify

      - name: Build (watchOS app)
        run: |
          set -euo pipefail
          udid=$(xcrun simctl list devices available --json \
            | jq -r '[.devices | to_entries[]
                      | select(.key | test("watchOS")) | .value[]
                      | select(.isAvailable)][0].udid')
          test -n "$udid" && test "$udid" != "null"
          xcodebuild build -project BadwaterIgnition.xcodeproj \
            -scheme BadwaterWatch -destination "id=$udid" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO | xcbeautify
```

Building the app scheme covers an embedded widget extension; the watch app needs
its own scheme and a watchOS simulator. Add a `BadwaterWatch` scheme in
`project.yml`.

Neither new surface can be meaningfully *tested* in CI — but both must
**compile** there. The `canImport(AppKit)` branches in `WatchView` rotted for
months for exactly this reason, and a widget extension is even easier to forget.

---

## Device verification checklist

Nothing below can be established from CI.

**Widget**
- [ ] Appears in the gallery in both families
- [ ] Shows the latest obs within seconds of logging
- [ ] Time and age are legible at a glance, in sunlight
- [ ] Flips to the overdue presentation at the cadence and shows **no PIG**
- [ ] "No obs logged" on a fresh shift
- [ ] Correct in dark mode and at accessibility text sizes

**Live Activity**
- [ ] Starts on the first obs of a shift
- [ ] Countdown runs without the app foregrounded
- [ ] Updates on a later obs rather than stacking
- [ ] Exactly one activity after force-quit and relaunch
- [ ] Ends on new shift

**Watch**
- [ ] Snapshot arrives with the phone locked and the app backgrounded
- [ ] Complication updates on the face
- [ ] A late-delivered snapshot renders by the *watch's* clock, not as fresh
- [ ] Watch app opens showing the last snapshot, not blank

**Cross-cutting**
- [ ] A real multi-day record migrates through `ObservationRecordStore` intact
      (carried over from 1.2 — still outstanding)

---

## What this plan does not do

- **No logging from the widget or watch.** Freezing a reading requires the
  capture card; that is policy, not an omission. Interactive widgets and watch
  logging are both out of scope for as long as that policy holds.
- **No history, charts or exports** on either surface. Both mirror one reading.
- **No `systemMedium` widget** in v1. Add it if `systemSmall` proves too tight.
