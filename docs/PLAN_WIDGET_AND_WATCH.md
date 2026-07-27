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
| 2. `RecordLocation` | **Done** |
| 3. Widget target | **Done** |
| 4. Timeline provider | **Done** |
| 5. Widget views | **Done** — rendering unverified, no device |
| 6. Reload on record mutation | **Done** — plan was wrong, see below |
| 7. Live Activity attributes | **Done** |
| 8. Live Activity presentation + lifecycle | **Done** — lifecycle unverified, no device |
| 9. `WatchSnapshot` | **Done** — 16 tests |
| 10–13. watchOS app + complication | **Done** — compiles; behaviour unverified |
| 14. Bundle-id / entitlement audit | **Done** — see the table below |
| 15. CI covers the new targets | **Done** — widget + watch schemes, wired with each target |

**Everything from Task 2 onward was written without a Mac**, contrary to the
note this section used to carry. What made that possible, and what it does and
does not establish:

- **Swift 6.1 for Linux** — the same version the `core-tests` container uses. So
  `swift test`, `swift run badwater-vectors --check` and
  `node conformance/check-web.js` are all real, and the core additions
  (`WatchSnapshot`, `GlancePhrasing`) are genuinely tested.
- **XcodeGen built from source on Linux** — `project.yml` is really generated
  and the resulting `.pbxproj` really inspected. This caught two spec errors
  before they reached a runner (below).
- **`swiftc -parse`** over every SwiftUI/WidgetKit/watchOS file — syntax only,
  not types.
- **CI's `macos-15` runner** for the actual `xcodebuild`, which is what caught
  the `Info.plist` traps. The full gate is **green**: iOS build, macOS build,
  widget extension, watchOS app + complication, `BadwaterIgnitionTests` and
  `BadwaterIgnitionUITests`.

What remains genuinely unverified is everything on the device checklist at the
end of this document: no rendering, no Live Activity lifecycle, no snapshot
delivery, and no complication has been seen working. Treat those as written but
unproven.

### Where the plan as written was wrong

Recorded because each one would otherwise be re-derived by the next reader.

1. **Task 3's `INFOPLIST_KEY_NSExtensionPointIdentifier` does not exist.** The
   `INFOPLIST_KEY_*` mechanism covers a fixed set of keys and `NSExtension` is
   not among them, so `GENERATE_INFOPLIST_FILE` produced a plist with no
   extension point. That builds, links, embeds and *validates* without
   complaint, then fails at install with `extensionDictionary must be set in
   placeholder attributes` — a message that never mentions the missing key. Both
   extensions now use a real `info:` block.
2. **Task 6's instruction missed two of the five mutation points.** "Wherever
   `rescheduleCadence()` is called" covers edit, delete and undo; **log** and
   **new shift** talk to the scheduler directly. Logging is the mutation the
   widget exists for.
3. **Task 13's `supportedDestinations: [watchOS]` is rejected by XcodeGen** —
   watch targets need `platform:`. This is the "least-standard part of this
   plan" the plan itself flagged.
4. **Task 14's entitlement list leaves the complication with no data.** It is a
   separate process from the watch app, so it cannot read the receiver's memory,
   and the phone's App Group does not cross the pairing. The watch pair needs
   its own group.
5. **`embed: true` works** on XcodeGen 2.43.0, answering Task 3's open question:
   it produces `Embed Foundation Extensions` for the widget and
   `Embed Watch Content` for the watch app.
6. **The watch app needs `WKApplication: true`.** Without it the installer reads
   the bundle as a legacy WatchKit 2.0 app and refuses to install the *containing
   iOS app* — so a missing key in the watch plist took out the phone's UI tests,
   three targets away. `WKRunsIndependentlyOfCompanionApp` belongs to the old
   WatchKit-extension layout and is not used here.

Four of these six only surface at **install** time, not build time. The
extensions and the watch app compiled, linked, embedded and *validated* clean
through every one of them. That is the case for Task 15's "wire CI as the target
is created" instruction, stated more strongly than the plan stated it: a green
compile establishes almost nothing about an extension or a watch app.

### Starting a fresh session

**All 15 tasks are written and merged** (#31, `e0aa43d`). What remains is not
code — it is the device verification checklist at the end of this document,
none of which has been run. Paste this:

> Finish `docs/PLAN_WIDGET_AND_WATCH.md` in `domalhambra/badwater-ignition`.
> **All 15 tasks are already written, merged and CI-green — do not re-implement
> any of them.** What's left is the **device verification checklist** at the end
> of that document, which has never been run: no rendering, no Live Activity
> lifecycle, no snapshot delivery and no complication has been seen working.
>
> Read `CLAUDE.md` first — the **display policy** guardrail is what every one of
> those checks is really testing.
>
> Work through the checklist on a real device with a paired watch, and fix what
> it finds. Start with the two items most likely to fail, both of which fail
> *silently*:
>
> 1. Confirm `NSSupportsLiveActivities` is actually present in the **built** app
>    bundle, not just in `project.yml`. If it isn't, `Activity.request` never
>    starts a countdown and nothing errors.
> 2. Confirm both App Groups are provisioned on the signing team —
>    `group.com.badwater.ignition` (app + widget) and
>    `group.com.badwater.ignition.watch` (watch app + complication). An
>    unprovisioned group doesn't error either; the surface is just permanently
>    empty, which reads like a data bug.
>
> Then the rest of the checklist. Tick items off in the document as they pass,
> and record anything the device disproves — several of this plan's assumptions
> were already wrong in ways only a real build caught.
>
> Work on branch `claude/firefighting-weather-calculator-refactor-mmkxgy` off the
> latest `main`. Verify with `swift test`,
> `swift run badwater-vectors --check conformance/vectors.json`,
> `node conformance/check-web.js`, and `xcodegen generate && xcodebuild build`.

Requirements for that session: macOS with Xcode 16+, `xcodegen`, `xcbeautify`, a
Swift 6 toolchain, and Node — **plus a physical iPhone and a paired Apple Watch**,
which is the part that actually gates this work now.

### Also outstanding, not on the checklist

- **No icon artwork.** The watch app's `AppIcon` set declares the watchOS slot
  and carries no images — the same state as the iOS `AppIcon`. Both need real
  art before submission.
- **CI runs every job twice.** The workflow triggers on both `push` (for
  `claude/**`) and `pull_request`, so each commit to a PR branch burns two
  macOS runners for an identical result and roughly doubles queue time. A
  `concurrency` group, or narrowing the `push` trigger, fixes it. Noticed while
  driving this plan's CI; deliberately not changed here, because a CI change
  mid-flight would have muddied the signal this work depended on.

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

## Task 14: Bundle-identifier and entitlement audit  ✅ DONE

Verified against the generated `.pbxproj` and the generated entitlements:

| Target | Bundle identifier | App Group |
|---|---|---|
| App | `com.badwater.ignition` | `group.com.badwater.ignition` |
| Widget | `com.badwater.ignition.widget` | `group.com.badwater.ignition` |
| Watch app | `com.badwater.ignition.watchkitapp` | `group.com.badwater.ignition.watch` |
| Watch complication | `com.badwater.ignition.watchkitapp.widget` | `group.com.badwater.ignition.watch` |

**Two groups, not one.** The plan said the watch gets no App Group because it
can't reach the phone's — correct, but it left the complication with nothing to
read. A complication is a separate process from the watch app, so it can't see
the receiver's in-memory snapshot either; it needs a file in a container they
both open. Hence `group.com.badwater.ignition.watch`, deliberately a *different*
identifier: nothing is shared across the pairing, and reusing the phone's would
imply to the next reader that something is.

`WKCompanionAppBundleIdentifier` on the watch app is `com.badwater.ignition`.

A mismatched group identifier presents as "the widget is always empty" — or "the
complication is always empty" — which is easy to misread as a data bug. Check
this first when either shows nothing.

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
- [ ] **`INFOPLIST_KEY_NSSupportsLiveActivities` actually reaches the built
      `Info.plist`.** Unlike `NSExtensionPointIdentifier` this one *is* a real
      build setting, but the failure mode if it isn't is silent —
      `Activity.request` simply never starts a countdown, with no error. Check
      the key is present in the built app bundle, not just in `project.yml`.
      This is the same class of trap as the widget's extension point and it is
      the one place in this work where it hasn't been ruled out.
- [ ] Both App Groups are provisioned on the signing team — the phone's and the
      watch pair's. Neither errors when absent; both just go empty.

---

## Simulator pass — 2026-07-27

First time any of these surfaces has been run. **Simulator, not device**, so
nothing below discharges the device checklist above — but several items that
were pure unknowns are now known to work, and one is now known to be broken.

Setup: Xcode 26.6, iPhone 17 Pro + paired Apple Watch Series 11 (46mm)
simulators. See [`RUNNING_LOCALLY.md`](RUNNING_LOCALLY.md).

**Confirmed working**

- `NSSupportsLiveActivities` **does** reach the built `Info.plist` (`true`).
  The plan's flagged likeliest-silent-failure is not one. Independently
  confirmed by the Live Activity actually starting.
- Widget and watch app are genuinely embedded — `PlugIns/BadwaterWidget.appex`
  and `Watch/BadwaterWatch.app` both present in the built bundle.
- Widget appears in the gallery and renders the logged obs from the App Group
  container: `Obs 0645 / PIG 40% · 40% s… / High · 4 min ago`.
- Live Activity **starts on the first obs of a shift** and its countdown **runs
  with the app backgrounded and the phone locked** (ticked 59 → 58 min on the
  lock screen). Shows no PIG, per the display policy.
- Watch app installs, launches, and shows the correct `No obs logged / Log one
  on the phone.` empty state.
- `WatchConnectivity` snapshot delivery **works** — the watch went from the
  empty state to `Obs 0645 · 40% · PIG unshaded · 40% shaded · High · just now`
  after the phone logged. Frozen value, with time and age.

**Found broken — now fixed**

- [x] **The `accessoryRectangular` widget truncated its own PIG line**, rendering
      `PIG 40% · 40% s…` and losing the one word that distinguished the two
      numbers. Fixed as part of the conditions rebalance below:
      ``GlancePhrasing/pigSummary(unshaded:shaded:)`` is now `PIG 40/40% shd`,
      with a test sweeping the range and asserting it stays under 18 characters
      and keeps its `shd` label.

**Open question, needs the device**

- The Live Activity countdown renders as `58:––` on the phone's lock screen —
  minutes tick, seconds show as dashes. Very likely system behaviour rather than
  a bug: it uses `Text(timerInterval:countsDown:)`, the documented API, and the
  *same* activity mirrored into the watch's Smart Stack renders full seconds
  (`58:54`). Confirm on the device and close it out.

---

## Conditions over PIG — 2026-07-27

A design correction, made after seeing the surfaces run. **PIG was being
over-indexed on.** It led every glanceable surface at display size while the
observation it derives from — dry bulb, RH, wind — was absent entirely. Those
three are what a crew actually reads; PIG is one derived input among several to
a decision.

So every glanceable surface now leads with the observation and PIG follows:

    Obs 0706
    75°F · RH 20% · N 0-3
    PIG 40/40% shd
    High · just now

**Core.** ``ObsGlance/Reading`` and ``WatchSnapshot`` gained `dryBulbF`,
`relativeHumidity` and `windSummary`. New shared phrasing —
``GlancePhrasing/conditions(dryBulbF:relativeHumidity:wind:)``, its
`conditionsCompact` variant for single-line families, and `pigSummary` — so the
wrist, the complication and the phone widget cannot word one record three ways.

Three decisions worth keeping:

- **The conditions fields are optional on the wire.** The phone that sends a
  snapshot is a separate binary from the watch that renders it and may be older.
  A missing field degrades one segment to `—` instead of failing the decode and
  blanking the face — the same reasoning as `behaviorRawValue`.
- **Unrecorded is not calm.** A missing wind renders `wind —`, never `Calm`, and
  a test asserts it. Dropping the segment would have implied a reading nobody
  took.
- **RH is labelled everywhere.** RH and PIG are both percentages on the same
  small screen; the conditions line always says `RH 20%`, swept by a test across
  0–100.

**Complication.** Circular and corner now show **RH** rather than PIG — the
single most decision-relevant number — labelled and dated, because unlabelled it
would be indistinguishable from the PIG this surface used to show. Inline
carries all three, ordered `time · temp · RH · wind` so that anything the system
truncates comes off the least critical end and the time anchor can never be what
is lost.

**Verified**: core suite 140 → 149 tests, vectors byte-identical, 1172 parity
checks green, iOS and watchOS schemes build, and the new watch layout was
confirmed rendering on the simulator with a real wind value and no truncation.
**Not re-verified visually**: the phone widget's new rendering — it uses the same
golden-tested phrasing and builds clean, but it has not been seen since the
change.

**Build fix required to get this far**

Xcode 26.6 rejected `ObsActivityController.swift` with three
`sending '…' risks causing data races` errors — `Activity<Attributes>` is not
`Sendable` in the iOS 26 SDK. CI (`macos-15`) accepts it. Fixed with
`@preconcurrency import ActivityKit`; a narrower `@unchecked Sendable` wrapper
around the three call sites would be tighter and is worth revisiting.

**CI is on an older Xcode than the development Mac.** Green CI did not mean it
built locally. Consider pinning CI to `macos-26`.

---

## What this plan does not do

- **No logging from the widget or watch.** Freezing a reading requires the
  capture card; that is policy, not an omission. Interactive widgets and watch
  logging are both out of scope for as long as that policy holds.
- **No history, charts or exports** on either surface. Both mirror one reading.
- **No `systemMedium` widget** in v1. Add it if `systemSmall` proves too tight.
