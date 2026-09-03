# REVIEW-6 - round 5, stage 5, item 10 (N3-6b), range `ff554cf..ce124f5`

Reviewed head `ce124f54281c3042b78a8478915b3d45243cec75`, branch `prod-readiness-5/2026-08-15`.
The range contains four commits: `07c00b2` (the R5 review artifact, `reviews-5/REVIEW-5.md` only, verified `--name-only`), `fcd4079` (the stamping commit, `PROD-READINESS-5.md` only, verified `--name-only`), `86afee0` (item 10), `ce124f5` (the ledger record, `PROD-READINESS-5.md` only, the range's HEAD).
At review time `git status --porcelain` showed only the untracked `.claude/`, `.mcp.json` and `CLAUDE.md`, all pre-existing, none touched by any range commit; `HEAD == ce124f5` before this file was added.
All mutation work was done in two detached worktrees under my scratchpad - one at `ce124f5`, one at `fcd4079` - never on the main tree; every mutated file was restored from a saved pristine copy and byte-compared with `cmp`, both worktrees were `git status --porcelain` clean before removal, and the pristine simulator suite was re-run green on the restored file after the battery.

verdict: PASS

## Summary

**The closure is real: both stage-start deletions reproduce green at `fcd4079` and die at the named tests at the head, every mutant I re-ran killed with the claimed failing set on every run, and all five dimensions land on the ledger's numbers to the digit.**
The reproduction is exact from both sides: at `fcd4079` with the delegate assignment deleted from `start()` AND the `willPresent` reschedule deleted, the full host suite is 232 of 232 green and the full simulator suite is **133 / 73 / 67, 10 known issues, `** TEST SUCCEEDED **`** - the ledger's stage-start figures verbatim; the same two deletions applied together at the head fail exactly "start() installs the coordinator itself as the notification delegate" (2 issues) and "willPresent's body reschedules and keeps the banner" (1 issue) and nothing else.
Both seams pass the recorded rule by inspection: `BackgroundTaskRegistering` mirrors `BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)` parameter-for-parameter with an empty `extension BGTaskScheduler: BackgroundTaskRegistering {}`, `installDelegate` is one assignment in the `UNUserNotificationCenter` conformance and one forward in `LiveNotificationClient`, and the REJECTED narrowing is rejected for the right reason - handing the handler `any BackgroundRefreshTask` would force the `as? BGAppRefreshTask` downcast into the live conformance, which is exactly the logic-behind-the-seam shape `LiveNotificationClient.swift:15-18` forbids.
Production invariance holds by diff and by construction: `OttoApp.swift` has a zero-line diff across the range, both new parameters default to nil and resolve to `BGTaskScheduler.shared` / `UNUserNotificationCenter.current()`, and registration is still a synchronous statement inside `start()`.
The timezone test drives the real observer - it posts `NSSystemTimeZoneDidChange` to `NotificationCenter.default` with `passes == 0` asserted before the post - and M6, which empties only that observer's body, kills only that test on all three runs, which also proves the two observers are separate registrations.

No findings.
The residual floor is honest: I enumerated the unreached surface myself and found nothing beyond what the ledger names, apart from one pre-existing line outside the item's entry points, recorded in the attempted refutations below.

## What I ran

All measurements at `ce124f5` unless stated.
Host: macOS (Darwin 24.6.0), arm64, simulator `<simulator-udid>`; `xcodebuild test` run from `Packages/OttoUI/` as the round's procedure requires.

### The five dimensions at the stage-5 head

| dimension | ledger claims | measured here | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0, 265/127/233 = 625 | **exit 0; OttoDomain 265 / OttoPersistence 127 / OttoUI 233 = 625**, from a clean clone of `ce124f5` | exact |
| `swiftlint --strict` | clean, 234 files | **0 violations, 0 serious in 234 files** | exact |
| simulator suite, full | 134/73/75, 10 known issues, `TEST SUCCEEDED` | **134 / 73 / 75, 10 known issues, `** TEST SUCCEEDED **`** on three pristine full runs - two before the battery, one on the restored file after it | exact, and no ordering flake surfaced across the three runs plus eleven mutant runs of the `.serialized` suite |
| non-Gregorian harness | 0 / 0 / 0, 233 tests per locale | **exit 0 under all three**: `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`, 233 tests passing each, via `swift build --build-tests` plus `swiftpm-testing-helper` per the `CalendarEraTests.swift` header | exact |
| flake, twelve full host runs | 12 of 12 (233 tests per run) | **3 dedicated full host runs green at 233**, plus verify.sh's own run and the three 233-test harness runs; I did not re-run twelve | consistent; the 12/12 itself is unreplicated, the same caveat REVIEW-4 and REVIEW-5 recorded |

### The stage-start reproduction, re-executed at `fcd4079`

Worktree at `fcd4079`, both deletions applied by a script asserting each target text occurs exactly once: `UNUserNotificationCenter.current().delegate = self` deleted from `start()`, and `await MainActor.run { _ = self.rescheduleSoon(.notificationDelivered) }` deleted from `willPresent`.
Measured: full host suite **232 of 232 green** (vacuously - the coordinator is `#if os(iOS)` and compiles to nothing on the host, as the ledger itself says), and the full simulator suite **133 / 73 / 67, 10 known issues, `** TEST SUCCEEDED **`**.
That is N3-6b executing at the stage start, to the ledger's exact figures; the file was restored byte-identical afterwards.

### The same deletions at the head

M1 and M5 below are the two deletions individually at their new spellings; applied **together** in one tree at `ce124f5` - the reproduction's shape - the full simulator suite fails with exactly 3 issues beyond the 10 known: "start() installs the coordinator itself as the notification delegate" (2) and "willPresent's body reschedules and keeps the banner" (1).
The void the item existed to close is closed from both directions.

### The battery, reproduced

Each mutant applied by a script asserting the target text occurs exactly once, in the worktree at `ce124f5`, restored from a pristine copy verified with `cmp` after each; every run is a FULL simulator-suite run with no scoping, and the 10 standing known issues appeared with unchanged total on every mutant run.

| ledger mutant | exact change I applied | ledger says | measured |
|---|---|---|---|
| M1 | `client.installDelegate(self)` deleted from `start()` | "start() installs the coordinator itself as the notification delegate", 2/2/2 | **the same one test, 2 / 2 / 2**, three full runs; the two issues are `installCount == 1` and the delegate-identity `===` |
| M3 | `==` to `!=` in `notificationResponseReceived` | "a real action identifier reaches the handler unmapped", 1/1/1 | **the same one test, 1 / 1 / 1**, three full runs; the failure is `.openDetail` published for the inverted-to-"" action, exactly the asymmetry the ledger's M3 paragraph states, and the plain-tap test stayed green under inversion as that paragraph predicts |
| M6 | the timezone observer's `MainActor.assumeIsolated { _ = self?.rescheduleSoon(.timeZoneChange) }` emptied | "a system timezone change runs a pass", 1/1/1 | **the same one test, 1 / 1 / 1**, three full runs; the significant-time-change test stayed green, so the test reaches its observer through the real `NotificationCenter.default` post, not a shortcut |
| M5 | `rescheduleSoon(.notificationDelivered)` deleted from `notificationWillPresent` | "willPresent's body reschedules and keeps the banner", 1/1/1 | **the same one test, 1 issue** (one full run; the M1+M5 combined run above is its second execution) |

M2 (identifier corrupted) and M4 (the `.notificationAction` reschedule dropped) were not re-run; their claimed kill sets are the same tests my M1/M3/M5 reproductions exercised from adjacent directions, and the identifier and queue assertions they target were read in the test source.
The pristine full simulator suite was re-run on the restored file after the battery: **134 / 73 / 75, 10 known issues, `** TEST SUCCEEDED **`**.

## Findings

None.

## Explicit checks

- **The seam rule, both seams.** `BackgroundTaskRegistering.register(forTaskWithIdentifier:using:launchHandler:)` matches the framework signature exactly (`String`, `DispatchQueue?`, `@escaping (BGTask) -> Void`, `-> Bool`); the conformance is an empty extension, zero logic. `installDelegate(_:)` is `self.delegate = delegate` in the `UNUserNotificationCenter` conformance and `center.installDelegate(delegate)` in the client - a forward and nothing else, and the recording fakes hold the delegate weak as the real center does. Neither fake can mock away logic under test: the fakes record what crosses the boundary and invoke nothing.
- **Production invariance, executed on the diff.** `git diff ff554cf ce124f5 -- Otto/App/OttoApp.swift` is empty; the composition root still passes no `taskRegistrar` and no `center`, both defaulted-nil parameters resolve to the live singletons in the initializers, and `taskRegistrar.register` is a synchronous statement inside `start()` before it returns - the `OttoApp.swift` comment at the `coordinator.start()` call site binds unchanged.
- **Test integrity.** `NotificationCoordinatorTests.swift` and `SchedulingGateIntegrationTests.swift` have a zero-byte diff across the range; `NotificationCoordinatorStubs.swift` gains exactly one line, a no-op `installDelegate`; the range touches no other existing test file, so nothing was weakened anywhere in it.
- **The reader count, re-enumerated by the baseline's method.** `actionLogLines` 4, `schedulingLogLines` 2, `boundaryLines` 1, `OttoLogProbe.persistenceLines` 3 - **ten**; no `OSLogStore` construction or `getEntries` call exists anywhere in `Tests/OttoUITests`.
- **The trigger-TAG disclosure, verified structurally.** The `ReminderScheduling` requirement is three-parameter; the trigger exists only in the `OttoLog` extension wrapper, so no fake behind the seam can ever see it, and no test ties either observer to its enum case - swapping `.timeZoneChange` and `.significantTimeChange` changes only a log tag, exactly as the floor discloses.
- **The residual floor, enumerated myself.** Unreached at the head: the launch closure body (the downcast, the rejection branch and the dispatch, `NotificationCoordinator.swift:88-95`), the two `nonisolated` wrappers (`:327-332`, `:349-357`), the `registered id=... accepted=` notice content, and the composition-root `start()` call - each named by the ledger. Nothing else in the item's entry points is unreached; the one adjacent unreached line outside them is recorded in the attempted refutations.
- **The arithmetic.** Host 232 -> 233 is `installDelegateForwards`; simulator 133/73/67 -> 134/73/75 is +1 (the new host test compiling for the simulator in the 134 bundle) and +8 (the start suite - eight `@Test` functions counted in the file - in the 75 bundle); lint 232 -> 234 is `BackgroundTaskSeams.swift` plus `NotificationCoordinatorStartTests.swift`. All reconcile exactly.
- **The file-length split is genuine.** `NotificationCoordinator.swift` was 363 lines at `fcd4079` and is 382 at the head; the seams file is 50 lines, so the unsplit file would sit past SwiftLint's 400-line file_length cap, and the split predates nothing - it lands in the same commit as the seam that caused it.
- **Scope and hygiene.** Four commits, all inside the declared R6 and matching the REVIEW RANGES row; every message one short sentence, no body, no trailer; no `Package.swift`, `project.yml`, `.swiftlint.yml`, workflow, target, product or dependency change anywhere in the range; the two record-only commits touch exactly the one file each claims; `.claude/`, `.mcp.json` and `CLAUDE.md` are untracked, pre-existing and untouched.

## Attempted refutations that did not become findings

- **A start suite that survives a gutted `start()`.** Walked the body statement by statement: `registerCategories`, `installDelegate`, the registration (identifier literal AND `.main` queue identity), and both observers each have a test that dies without them - M1 and M6 demonstrate two of these by execution. The only unpinned statements are the `registered` notice line and its `accepted=` value, which the floor discloses.
- **The timezone test shortcutting past the observer.** The test posts `NSSystemTimeZoneDidChange` to the process-global center with `passes == 0` asserted first; M6's kill - the observer's body emptied, only that test red, the significant-time test green - proves the delivery path is the real observer registration and the two registrations are distinct.
- **M3 read wrong.** Under inversion the plain-tap test stays green because `route`'s `case nil` treats the unmapped default identifier as a tap (`NotificationActionHandler.swift:175-178`), so inversion is visible only on the real-action side - the ledger's own caveat paragraph, confirmed by execution and by reading the handler.
- **Fake-internal bookkeeping instead of observable work.** The assertions are the boundary crossings themselves - the categories handed over, the delegate identity, the identifier string, `queue === DispatchQueue.main`, pass counts through the same `ReminderScheduling` seam production uses - plus behaviour on the extracted bodies (`[.banner, .sound, .list]`, `.openDetail`, `.none` not published).
- **A third singleton touchpoint the ledger does not name.** `scheduleNextBackgroundRefresh` still calls `BGTaskScheduler.shared.submit` bare, and its success branch (`re-armed earliestBegin=+24h`) is unreachable in this rig because the simulator refuses the submission. Dismissed as a finding: it is not in `start()` or the delegate methods - item 10's entry points - it predates the range unchanged, and the ledger's "two singleton touchpoints" sentence is scoped to `start()`, where it is true. Recorded here so the next round sees it.
- **The floor's `:88-93` span.** The ledger cites `NotificationCoordinator.swift:88-93` for the launch closure and names the dispatch into `handleBackgroundRefresh` as part of it; the dispatch sits at `:94`. The content enumeration is correct and the span is a pointer, not a census - a nit, not a finding.
- **`.serialized` ordering flake.** Three pristine full runs plus eleven mutant runs, every one with the start suite executing; no unexpected failure appeared in any of them, and every red test across the battery was the mutant's own target.
- **Known-issue drift under mutation.** The per-test placement of the 10 known issues varied slightly between runs (a rendering half landing on a different sibling), but the total was 10 on every run, mutant and pristine alike - the suite total is the stable property and it never moved.
- **The `@discardableResult` on the protocol requirement as a signature deviation.** The framework method's result is used at the call site (`let registered =`), the attribute adds no logic and hides none, and the parameter list and types are byte-for-byte the framework's - dismissed.

## What I could not check, and why

- **The 12-of-12 flake dimension.** Three dedicated pristine host runs plus verify.sh's and the three harness runs, all green at 233; twelve were not re-run, so the ledger's flake figure is sampled, not replicated - the same caveat the last two reviews recorded.
- **M2 and M4.** Not re-run (M1/M3/M5/M6 and the combined reproduction were); their claimed kill sets sit on the same tests my runs exercised from adjacent directions.
- **The launch closure, the wrappers, and the `registered` notice content.** Unreachable by construction in this rig (`BGTask`, `UNNotification`, `UNNotificationResponse` have no public initializers; an eleventh `OSLogStore` reader is forbidden) - the floor's own statement, which is why they are the floor.
- **CI-runner delivery, release configuration, a physical device.** Standing CANNOT ASSESS, as every prior round.
