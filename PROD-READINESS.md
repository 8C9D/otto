# PROD-READINESS — Otto

Independent production-readiness sweep, 2026-08-10, branch `prod-readiness/2026-08-10`, from commit `406a5a6`.
Baseline artifact: `reviews/BASELINE.md`. Review trail: `reviews/`.

This document is a state assessment plus a bounded diff. It is not a claim that the app is ready.

---

## Context, established by inspection

**Stack.** Swift 6 (`SWIFT_VERSION: "6.0"`, `SWIFT_STRICT_CONCURRENCY: complete` — `project.yml:20-22`), SwiftUI, SwiftData, iOS deployment target 26.0.
Four modules: the app target `Otto/` (composition root, one file), and three local Swift packages — `OttoDomain` (pure values, imports only Foundation), `OttoPersistence` (SwiftData + repository protocols), `OttoUI` (`OttoServices`, `OttoStores`, `OttoUI`).
203 Swift files, ~32,700 lines including tests. No third-party dependencies of any kind: every `Package.swift` declares only local targets. Nothing to CVE-check, and nothing was found.

**Package manager.** SwiftPM for the packages; XcodeGen (`project.yml`) generates the `.xcodeproj`, which is gitignored and not committed.

**Build / test / run, taken from `project.yml`, `.github/workflows/ci.yml`, `scripts/verify.sh` and the README, and executed to confirm:**

| Command | Confirmed |
|---|---|
| `scripts/verify.sh` | ✅ exit 0, 526 tests |
| `swift test --package-path Packages/{OttoDomain,OttoPersistence,OttoUI}` | ✅ via verify.sh |
| `xcodegen generate` | ✅ via verify.sh |
| `xcodebuild build -scheme Otto -destination 'generic/platform=iOS Simulator'` | ✅ via verify.sh |
| `swiftlint --strict` | ✅ clean |
| `xcodebuild test -scheme OttoUI-Package -destination "id=<sim>"` | ✅ exit 0, 19 tests, 7 known issues |

**How it ships.** Sideloaded development build, signed with `DEVELOPMENT_TEAM: <team-id>`, `CODE_SIGN_STYLE: Automatic`, bundle id `com.arthurzhang.otto`, installed on one physical iPhone. `aps-environment: development` (`project.yml:80`). To ship it to anyone else would require: a distribution signing identity, a non-development APS environment, a provisioned CloudKit container if sync is ever enabled, and TestFlight or ad-hoc provisioning per device. None of that exists today and none of it is in scope here.

**Boundaries — both lists verified, not accepted.**

Present, as the prompt predicted:
- Local persistence — SwiftData over SQLite, two containers (`OttoContainerFactory.swift:63-78`), staged migration plan pinned at V3.
- Notifications — `UNUserNotificationCenter` behind the `UserNotificationCentering` seam (`LiveNotificationClient.swift:19-27`).
- Background execution — `BGTaskScheduler`, identifier `com.arthurzhang.otto.refresh` (`NotificationCoordinator.swift:21`, `project.yml:67-68`).
- File system — JSON + CSV export to `FileManager.default.temporaryDirectory` (`ExportService.swift:88`), pre-sync backup to Documents (`SyncActivationService.swift:60`), import via `.fileImporter`.
- Device clock — `DateProvider.live` (`DateProvider.swift:31-43`).

Absent, verified:
- **Network: confirmed absent.** `grep -E "URLSession|URLRequest|NWConnection|CFNetwork|http://|https://"` across all four source trees returns zero hits. The app makes no network calls. (The `remote-notification` background mode and the iCloud entitlement are declared for a future CloudKit wave; `cloudKitDatabase` is `.none` on every configuration — `OttoContainerFactory.swift:66-104`.)
- **Auth, payments, third-party APIs, server-side anything: confirmed absent.** No authn/authz surface, no injection surface, no request deserialization. Passes that assume those boundaries are skipped, not reinterpreted.

**What can actually be executed to verify a change:**
- **Host `swift test`** reaches all of `OttoDomain`, all of `OttoPersistence` (SwiftData works headless with in-memory and on-disk containers), and the `OttoStores` / `OttoServices` / `OttoUI` test targets. 526 tests. This is where nearly all verification in this run happens.
- **Simulator** is needed for the UIKit-hosted suites and for the app target's real launch path. Available and used. **On this host it vends no accessibility tree**, so label assertions there are inert (see `reviews/BASELINE.md`).
- **Hardware** is needed for: `BGTaskScheduler` actually launching a task, real notification delivery and Focus/interruption-level behavior, real file protection at rest, and Release-configuration behavior on device. **Touching the device is prohibited this run.** Every finding below whose fix can only be confirmed on hardware is marked **UNVERIFIED** individually, not once at the end.

**What "production" means here — who breaks if this breaks.**
Derived from `README.md:3-6` ("reminds you before a subscription renews or a free trial converts to paid, and it verifies that a subscription you cancelled actually stopped charging you"), the spec at `docs/Subscription-Tracker-Spec.md`, and the entry points.
One person, on one phone, with real money at stake. The app never acts — it never cancels, never logs in, never touches a payment method. Its entire value is that it speaks at the right moment. So the person who breaks is the user who is charged for something they meant to cancel, or who believes a cancellation stuck when it did not, or who loses the record of what they pay for. The characteristic failure is **silence on a phone in a drawer**, which throws nothing and crashes nothing. Severity below is weighted to that, not to uptime.

---

## Findings

Severity: **P0** = money, silence, or data loss. **P1** = fails under realistic input or scale, or is undiagnosable after the fact. **P2** = everything else.
Provenance: **INDEPENDENT** = found by reading the code in this run. **CONTAMINATED** = disclosed to this run before the ledger was written (see the contamination disclosure in `reviews/BASELINE.md`); this run makes no claim to have found it independently.

| id | area | sev | prov | evidence (file:line) | fix | blast radius |
|---|---|---|---|---|---|---|
| F1 | date/calendar | P1 → **DEFERRED** | INDEPENDENT | `OttoStores/DateProvider.swift:34` reads `Calendar.current.dateComponents([.year,.month,.day])` and feeds the result straight into `CalendarDay`, whose arithmetic is **proleptic Gregorian by construction** (`OttoDomain/Models/CalendarDay.swift:66-72`, `:44-57`) and whose only instant conversion hard-codes `Calendar(identifier: .gregorian)` (`:178`). Same defect at `OttoUI/CalendarDayBinding.swift:7,16`, `OttoStores/DisplayFormatting.swift:33`, and — **added by R0-8** — `OttoUI/InsightsView.swift:137-145`. | **ATTEMPTED IN PASS 2, REJECTED BY REVIEW 2, REVERTED (`b582d94`). NOW DEFERRED — see DEFERRED for the discovered scope.** | **Amended by R0-2** — the ledger originally claimed one mechanism where the code has two, contradicted by its own measurements. Buddhist (2569) and Hebrew (5786) resolve to *future* instants and never fire. Japanese (8), Islamic (1448), ROC (115) and Persian (1405) resolve to instants in the **past**, which take the catch-up branch at `NotificationScheduler.swift:348` and emit a 5-second interval trigger (`:360`, `:23`) — up to 64 notifications firing seconds after *every* pass, repeating as the user clears them. Both modes are total breakage. Zero for a Gregorian device. |
| F2 | notifications / error handling | P1 | INDEPENDENT | `OttoServices/NotificationCoordinator.swift:234` — `let followUp = try? await handler.handle(…)`. `NotificationActionHandler.swift` contains **no logging at all** (verified: `OttoLog` appears nowhere in that file). | Log the failure on `OttoLog`; do not discard it. Surfacing to the UI is a separate, deferred question. | The user's answer to a notification is destroyed with no trace. "Remind me later" is the terminal case: `snooze` (`NotificationActionHandler.swift:150`) is the *only* thing that action does, the system has already consumed the notification, and a throw there means the reminder simply ceases to exist. "Yes — it stopped" and "Keeping it" partially self-heal on a later pass; the snooze does not. |
| F3 | notifications / honesty | P1 | INDEPENDENT | `OttoStores/NotificationStatusStore.swift:43-47` — the `catch` refreshes `permission` and leaves `outcome` untouched. `OttoUI/TodayView.swift:187-193` renders `"Reminders scheduled through \(coveredThrough)."` from that stale `outcome`. Compounded by `NotificationCoordinator.swift:113-119`, where `rescheduleSoon` swallows with `try?` and so never calls `onOutcome` on a failed pass. | Clear or invalidate `outcome` when a pass fails, so Today stops asserting coverage it no longer has. | Today keeps stating a coverage date derived from the last *successful* pass, indefinitely. The screen whose stated job is "never fail silently when it cannot send" (`NotificationStatusStore.swift:7-9`) is exactly where the false reassurance appears. |
| F4 | notifications / Focus | P1 | INDEPENDENT | `OttoServices/NotificationActionHandler.swift:159` hard-codes `isTimeSensitive: false` for every snooze, while the kind is carried through faithfully (`:148`, `:189-191`) and `.trialDayOfMorning` / `.trialDayOfEvening` are time-sensitive in the plan (`OttoDomain/Scheduling/PlannedReminder.swift:45`). | Derive `isTimeSensitive` from `kind.isTimeSensitive`, as the scheduler already does at `NotificationScheduler.swift:345`. | Snoozing the cancel-by-day warning silently downgrades it out of Focus breakthrough. The user asks to be reminded later about the one deadline that costs unrecoverable money, and the later reminder is the one that can be held by a Focus mode or Scheduled Summary. **UNVERIFIED on hardware** — Focus behavior is not observable in the simulator. |
| F5 | notifications / partial failure | P1 | INDEPENDENT | `OttoServices/NotificationScheduler.swift:180-183` — `for spec in specs where … { try await client.add(spec) }`. The first throw aborts the loop; every remaining rung is never added. The throw reaches `rescheduleSoon`'s `try?` (`NotificationCoordinator.swift:114`). | Collect per-spec failures and continue, mirroring `reconcileLedger`'s existing per-subscription tolerance (`NotificationScheduler.swift:279-281`); report them in `ScheduleOutcome`. | One rejected `add` silences every rung ordered after it. The pass *is* logged (`OttoLog.swift:91-95`), so it is diagnosable — but the user sees F3's stale coverage line and no error. Ordering is deterministic, so the same rungs lose every pass. |
| F6 | data / restore | P1 | **CONTAMINATED** | `OttoUI/SettingsView.swift:293-294` — an empty database takes `.merge` with no prompt; `.merge` maps to `watermarks: .keep` (`OttoServices/ExportService.swift:78-81`); a nil watermark makes materialization start from today (`OttoPersistence/Store/OttoStore+BillingEvents.swift:53-54`). | Decouple the watermark policy from the merge strategy: reconstruct whenever the database was empty, independent of strategy. **Amended by R0-6:** the destination path `reconstructWatermarksNow` (`OttoStore+DataTransfer.swift:202-238`) deletes every row at `:214-221` and re-creates only for subscriptions surviving three filters at `:203-205`, `:223-225` — a tombstoned-then-resurrected subscription returns with a nil watermark. That hole is **NEXT ROUND**, not this fix. | The empty database **is** the recovery case — restore after reinstall — so the default path is the wrong one. Confirmed independently by reading the cited lines; disclosed to this run beforehand, so it is not evidence about this sweep's reach. |
| R0-1 | notifications / honesty | P1 | REVIEW 0 | `OttoServices/ScheduleOutcome.swift:18-21` declares `ledgerFailures` as "not swallowed"; its only consumers are `NotificationScheduler.swift:94,:144` (populate) and `OttoLog.swift:87` (logs a count). **Nothing in `OttoUI/` reads it.** `TodayView.swift:61-63,113` gates the coverage footer on permission only, never on `ledgerFailures.isEmpty`. | Gate the coverage claim on an empty `ledgerFailures`, reusing the existing footer. | The opposite shape from F3: a **fresh, successful** outcome that is itself an overstatement. A subscription whose `materializeEvents` threw has no rows and no reminders this pass, while Today states its reminders are scheduled for ninety days. F3's fix does not close it. |
| F7 | data / clock | P1 | **CONTAMINATED** | Merge resolution orders on `updatedAt` (`OttoDomain/Export/ImportResolution.swift:161`) and the device clock is not monotonic. | Described only. | Recorded for completeness. Full prior analysis lives in `docs/sync-safety.md`; this run adds nothing to it and does not fix it. |
| F8 | export / exposure | P2 | INDEPENDENT | `OttoUI/SettingsView.swift:185` — `.task { await regenerate() }` writes **both** exports on every appearance of the Settings screen (`:201-208`), unrequested, to `FileManager.default.temporaryDirectory` with no protection class specified (`OttoServices/ExportService.swift:87-91`). | Generate on demand rather than on appearance. **R0-10(b):** the same fix also closes the stale-`ShareLink`-after-import defect. | A complete unencrypted financial record — every vendor, amount, and the payment method's last four — is written to disk merely by visiting Settings, and accumulates one dated pair per day. Mitigating: `tmp` is excluded from iCloud/iTunes backup and is not reachable by other apps on a non-jailbroken device, and the default protection class still requires first unlock. That mitigation is why this is P2 and not higher. |
| F9 | export / correctness | P2 | INDEPENDENT | `OttoDomain/Export/ChargesCSV.swift:64-69` — `csvField` implements RFC 4180 quoting only; it does not neutralize a leading `=`, `+`, `-`, or `@`. | Prefix at-risk fields. | A subscription the user named `=1+1` or `=HYPERLINK(…)` becomes a live formula when the CSV is opened in Numbers or Excel. Self-inflicted only — the user types their own vendor names, there is no untrusted input path — which is why this is P2. |
| F10 | concurrency | P2 | **CONTAMINATED** | `OttoServices/NotificationCoordinator.swift:112-120` — `rescheduleSoon` spawns an unstructured `Task` per trigger with no coalescing; five `rescheduleSoon` sites can overlap (`:94`, `:99`, `:108`, `:220`, `:245`), plus the background `Task` at `:152` and `NotificationStatusStore.reschedule()`. `NotificationScheduler.reschedule` is actor-isolated but suspends at `:75`, `:93`, `:94`, `:116`, `:117`, `:127`, `:130`, `:137`, so passes interleave. | Serialize or coalesce passes. | Bounded, not zero: `OttoStore` is a `@ModelActor` and `materializeEvents` runs without suspension, so no duplicate ledger rows. The exposed window is a stale pass computing `stale` from a `pending` snapshot older than a concurrent pass's adds. Adds are idempotent replaces and removes never touch a desired rung, so the sets converge on the next pass. **UNVERIFIED** — not reproduced. |
| F11 | observability | P2 | INDEPENDENT | `OttoLog` defines exactly two categories, `background` and `scheduling` (`OttoServices/OttoLog.swift:27-31`). Verified by grep: there is no logging on **import/export** (`ExportService.swift`), on **cancellation or verification** (`SubscriptionFlowService.swift`), or on **notification actions** (`NotificationActionHandler.swift`). | Add boundary logging to those three paths. **R0-10(a):** include `.fileImporter`'s dropped `.failure` half. **R0-4:** the premise must also cover the `persistence` logger at `OttoStore.swift:8`, which is outside `OttoLog`. | Pass 5 of this run's own brief names "import/export" and "cancellation verification" as boundaries that must be observable. They are not. After a restore that went wrong while nobody was watching, the device holds no record that a restore was even attempted. |
| R0-5 | data / watermark | P2 | REVIEW 0 | `OttoPersistence/Store/OttoStore.swift:76` — `rows.first?.lastMaterializedThrough.flatMap(CalendarDay.init(yyyymmdd:))` turns a *corrupt* packed day into the same `nil` an *absent row* produces (`StorageShapes.swift:17-19`). Neither path logs. `rows.first` is also taken from an unsorted fetch with no unique constraint. | Distinguish absent from corrupt; log the corrupt case. | Reproduces F6's exact failure signature — materialize from today — by a second, unlogged route. |
| R0-6 | data / restore | P2 | REVIEW 0 | `OttoPersistence/Store/OttoStore+DataTransfer.swift:214-221` deletes every watermark row unconditionally; `:222-231` re-creates one only for subscriptions surviving the filters at `:203-205` and `:223-225`. | Rebuild for resurrectable subscriptions too. | A subscription tombstoned at reconstruct time and later resurrected by a merge (`ImportResolution.swift:161-168`) returns with a nil watermark. |
| R0-9 | tests / migration guard | P2 | REVIEW 0 | `OttoPersistence/Tests/.../CloudKitCompatibilityTests.swift:26-38` relates `OttoContainerFactory.mainSchema` to `OttoMigrationPlan.schemas.last` but never relates `stages` to `schemas`, which `OttoMigrationPlan.swift:13-19` keeps as two independent literals. | Assert `stages.count == schemas.count - 1`. | Appending `OttoSchemaV4` to `schemas` without a stage leaves this suite green while the data carry-over does not exist. The contract's own named hazard, in its next form. |
| R0-10 | export/import | P2 | REVIEW 0 | (a) `OttoUI/SettingsView.swift:235-239` handles only `.success` from `.fileImporter`; the `.failure` half is dropped with no log and no alert, though both exist at `:275-285`. (b) `SettingsView.swift:22-23,185` runs `regenerate()` once on `ExportSection` appearance, so after an import in the same visit `ShareLink` at `:165-169` still hands out the pre-import file under a footer calling it "the complete backup". | (a) folds into F11's logging; (b) folds into F8's on-demand generation. | (a) a genuine read error on the recovery path is indistinguishable from a user cancel afterwards. (b) the user shares a stale backup believing it is current. |
| R0-11 | persistence | P2 | REVIEW 0 | `OttoPersistence/Store/OttoStore+BillingEvents.swift:176-184` — the tombstone at `:176-177` is unconditional, the append at `:178` is guarded by `try?`, and the save at `:182-183` is conditional on that append. | Save on mutation, not on successful mapping. | If every tombstoned candidate fails `toDomain()`, the method returns `[]` ("nothing invalidated") while the shared context holds uncommitted soft-deletes that an unrelated later `save()` commits. Needs a partially-synced row shape; narrow today, anticipated for Wave 6B. |

### Prompt defects found (reported, not fixed)

| id | evidence | why it matters |
|---|---|---|
| PD1 | The prompt states "This project has `verify.sh` at the repo root". It is at `scripts/verify.sh`. | Trivial, but it is the file every other claim in the run is measured against. |
| PD2 | Stage 0 forbids reading the project's defect lists; Stage 0 mandates running `verify.sh`; `verify.sh` prints `docs/next-wave.md` in full (`scripts/verify.sh:117-118`), which **is** that defect list. | The two instructions cannot both be obeyed. This destroyed the "most informative output of this entire run" before the first finding was written. Fully disclosed in `reviews/BASELINE.md`; findings tagged CONTAMINATED accordingly. |
| PD3 | The prompt asserts the notification suite's engine tests "ran against a fake whose `add` never throws" as a live hazard. At HEAD this is stale: `LiveNotificationClient.swift:11-18` documents the seam being moved *to* the system boundary precisely to fix that, and `Tests/OttoServicesTests/LiveNotificationClientTests.swift` exists. | The prompt's hazard list is one wave out of date. The hazard class is still real; the specific instance named is not. |

---

## ASSUMPTIONS

1. **The device calendar is Gregorian for both real users.** Undeterminable without touching the device, which is prohibited. Conservative reading taken: F1 is assigned **P1, not P0**, because the failure — though total and silent — is gated on a device setting neither known user is known to have changed. It becomes P0 unconditionally for any user in a region where a non-Gregorian calendar is the default (e.g. `th_TH`, `ar_SA`).
2. **`main` at `406a5a6` is the intended starting point.** The working tree was clean; no verification was possible that this is the reviewed-and-blessed state.
3. **Release configuration behaves as Debug** except where a finding says otherwise. Not verified: no Release build was produced this run, since the only Release evidence that matters is on-device and the device is prohibited.
4. **`tmp` is excluded from device backups** (documented Apple behavior, not measured here). F8's severity depends on this; if it were false, F8 would be P1.
5. **The 64-slot notification budget is not currently near exhaustion.** With three live subscriptions the plan is far under it. Not exercised at scale in this run.

## CANNOT ASSESS

- Whether `BGAppRefreshTask` actually launches, and on which queue. Requires hardware.
- Real notification delivery, Focus breakthrough, and interruption-level behavior (bears on F4). Requires hardware.
- File protection class actually applied at rest (bears on F8). Requires hardware.
- Release-configuration behavior of any kind. Not built this run.
- Accessibility-label rendering. No AX client on this host (see `reviews/BASELINE.md`).

## NOT DEFECTS

- **No secrets anywhere.** Source, `project.yml`, CI config, entitlements, and all 93 commits of history scanned for key/token/password/private-key patterns: zero hits. `DEVELOPMENT_TEAM: <team-id>` is a team identifier, public in any built binary, not a secret.
- **No network calls.** Verified absent, as above. The prompt says finding one would be a P0; there is none.
- **No known-vulnerable dependencies**, because there are no dependencies. Every package declares only local targets.
- **No `#if DEBUG` behavior divergence on any shipping path.** The only two occurrences (`OttoUI/Previews.swift:1`, `OttoUI/PreviewSupport.swift:1`) wrap preview-only code.
- **No `try!` and no force-unwraps on user-data paths.** The `precondition`/`fatalError` sites found are guarding genuinely impossible states, with one exception now tracked as F1's mechanism (`DateProvider.swift:38` traps only on an unrepresentable date, which the calendar bug does not produce — it produces a *representable wrong* one, which is worse).
- **`OttoLog` itself is privacy-clean.** It marks only opaque UUIDs, calendar days, and control-flow outcomes as `.public` (`OttoLog.swift:14-21`). **STRUCK IN PART by R0-4:** the original claim extended this to "any path", which is false. `OttoStore.swift:8` declares a third `Logger` outside `OttoLog` entirely, and `:122` logs a whole `MappingError` whose `.invalidValue` case can carry a trial conversion amount (`SubscriptionMapping.swift:153-159`) or a raw vendor URL (`StorageShapes.swift:53-58`). Default `Logger` interpolation is `.private`, which is why this is P2 — but by this project's own doctrine at `OttoLog.swift:19-21` ("`.private` redaction is a display rule, not a guarantee about what was written") the original claim was false as written.

## DEFERRED

- **F7** (clock monotonicity in merge resolution) — prior analysis exists in `docs/sync-safety.md` and it is scoped to the CloudKit wave.
- Anything requiring a **SwiftData schema change**: none of F1–F11 or R0-1–R0-11 does. The schema is untouched by every fix proposed above.
- **F1 — the whole calendar defect.** Attempted in pass 2, REJECTED by `reviews/REVIEW-2.md`, reverted at `b582d94`. **The fix as scoped in the ledger was wrong, and shipping it would have made a real user strictly worse off.**

  What the ledger's fix column missed: `LiveNotificationClient.swift:226-232` hands `UNCalendarNotificationTrigger` a bare `DateComponents` with **no calendar attached**, and iOS resolves those numbers in `Calendar.current`. So on a non-Gregorian device the two errors **cancel**: `DateProvider` writes an era-numbered year, and the trigger reads it back in the same era. Measured directly against the real `UserNotifications` API:

  | components | `nextTriggerDate()` |
  |---|---|
  | `y=2026`, no calendar (host Gregorian) | `2026-08-15 13:00 UTC` |
  | `y=2026`, `calendar=.buddhist` | **`nil`** |
  | `y=2569`, `calendar=.buddhist` | `2026-08-15 13:00 UTC` |

  Correcting only the four cited sites feeds the trigger a Gregorian 2026 that a Buddhist device resolves as 1483 CE — a past instant, `nextTriggerDate` nil, **no reminder can ever fire**, silently, while Today still asserts coverage. The partial fix converts a device that happened to work into a dead one. That is the exact failure this app exists to prevent.

  This does not make F1 a non-defect. The compensation is partial: it holds for *delivery* but not for `CalendarDay`'s own arithmetic — `daysIn(month:year:)` and `isLeapYear` apply Gregorian leap rules to an era-numbered year (2571 is not a leap year by that rule; the Gregorian 2028 it stands for is), and `NotificationScheduler.swift:334`'s past/future branch compares an era year resolved as Gregorian, so it always takes the calendar branch. The defect is real; the fix is bigger than the ledger said.

  **Why DEFERRED rather than remediated:** the per-pass rule is "if a fix's blast radius exceeds your prediction, revert that fix, move the finding to DEFERRED with the discovered scope, continue". The prediction was "nothing changes on a Gregorian device; the day becomes correct on a non-Gregorian one". The discovered scope is a coordinated change across `DateProvider`, the two display seams, `InsightsView`, **and the notification trigger boundary in `LiveNotificationClient`** — a subsystem no frozen finding cites. Worse, the complete fix is **unverifiable on this host by construction**: proving it needs a device set to a non-Gregorian calendar, and touching the device is prohibited. Shipping an unverifiable rewrite of the delivery path on a money app is the wrong call.

  **Required change, for whoever picks this up:** make the era explicit at *both* ends in one commit — Gregorian components in `DateProvider`/`CalendarDayBinding`/`DisplayFormatting`/`InsightsView`, **and** `components.calendar = Calendar(identifier: .gregorian)` on the trigger in `LiveNotificationClient.add`, checking that `pendingRequests()`'s readback at `:147-157` still round-trips. Verify on a device with the calendar set to Buddhist. Until then the app is correct on Gregorian devices and wrong on others, which is where it already was.

- **R5-1 (from `reviews/REVIEW-5.md`, P2)** — `handle`'s new success line cannot be told from a snooze that scheduled nothing: `snooze`'s two non-throwing early returns (`NotificationActionHandler.swift:161-163`, `:179-182`) reach the success branch, so a "Remind me later" that produced no reminder logs `handled action=otto.action.remindLater` exactly like one that worked. Only `snoozesSpared=` in the `scheduling` category contradicts it, indirectly.
- **R5-2 (from `reviews/REVIEW-5.md`, P2)** — F2's log emission has **no executable guard**: deleting both `OttoLog.actions` statements leaves the whole suite green. Review 5 showed a guard is achievable with `OSLogStore(scope: .currentProcessIdentifier)`, which read the exact line back inside the test process; it was not added here because it costs 11-27 s against a ~2 s suite and depends on the log daemon being readable. Whoever adds it should weigh that against the fact that an unguarded log line is precisely what rots unnoticed.

- **R4-1 (from `reviews/REVIEW-4.md`, P1)** — R0-1's coverage gate is all-or-nothing, so one subscription's ledger failure withdraws a statement that is still accurate for every other subscription. Worse, `.notificationStatus` renders only for a permission other than authorized (`TodayView.swift:63-65`), so for an authorized user whose engine has been failing since install, Today is **identical** to a healthy one: no coverage line, no anything. This run traded a false claim for silence, which is the lesser evil but still not right. Saying something true in its place is new user-facing copy, which the scope constraint forbids.
- **R4-2 (from `reviews/REVIEW-4.md`, P2)** — F3's coordinator half is unverified: `NotificationCoordinator` is inside `#if os(iOS)` and compiles to nothing under host `swift test`, so reverting `rescheduleSoon` to its pre-fix shape leaves all tests green. That path carries every unattended trigger (foreground, timezone, significant time change, notification delivered/acted on); only `.stateChange` reaches the tested store. Separately, `handleBackgroundRefresh` never calls `onOutcome` at all, so a background pass publishes nothing either way. This is the same gap `docs/next-wave.md` already carries as "simulator-hosted `NotificationCoordinator` tests".
- **R4-3 (from `reviews/REVIEW-4.md`, P2)** — `ScheduleOutcome.truncatedAfter` has no consumer anywhere: the budget can silently drop rungs past the truncation point and no surface says so. And `ledgerFailures` reaches the log only as a bare count (`OttoLog.swift:87`), so an investigation learns that some subscription failed but never which.

- **R3-1 (from `reviews/REVIEW-3.md`)** — `ExportService.performImport`'s new empty-database predicate is `current.isEmpty`, but `completeSnapshot()` includes tombstones, so a database whose every record is tombstoned is not `isEmpty`. It therefore still gets the merge-or-replace prompt, and choosing Merge there reproduces F6 exactly: nil watermark, rows between the file's last charge and today silently never created. The stated principle ("does this device have ledger progress worth keeping") is broader than the predicate that implements it. Reviewer measured this against the real store. Post-freeze discovery, so recorded rather than fixed.

- **R0-7's stored-data repair** — repairing calendar days already written under a non-Gregorian device calendar. A migration/repair pass over stored user data is a new user-visible capability, which the scope constraint forbids. Required change described in NEXT ROUND.

## THE FROZEN WORK LIST

Frozen at Review 0 (`reviews/REVIEW-0.md`, verdict PASS-WITH-FINDINGS). The P0 and P1 findings surviving that review are the definition of done for this run. There are **no P0 findings**; Review 0 examined that and found the zero-P0 posture defensible under "be stingy with P0".

**8 findings, under the 15 cap, so nothing was moved to NEXT ROUND for capacity.** Ordering within the band is by blast radius, smallest first.

| # | id | pass | terminal state |
|---|---|---|---|
| 1 | F4 | 4 | **RESOLVED** — `c7bfe46`; UNVERIFIED on hardware (Focus behavior) |
| 2 | R0-1 | 4 | **RESOLVED** — `c7bfe46`, re-tested after Review 4 |
| 3 | F3 | 4 | **RESOLVED (store path)** — `c7bfe46`; coordinator path UNVERIFIED, see NEXT ROUND |
| 4 | F5 | 4 | **RESOLVED** — `c7bfe46` |
| 5 | F2 | 5 | **RESOLVED** — `58695c2`; emission evidenced by a unified-log artifact on **macOS host only**, UNVERIFIED on device, and carries no executable guard (see NEXT ROUND) |
| 6 | F6 | 3 | **RESOLVED** — `b15b0a6`, remediated after Review 3 |
| 7 | F1 | 2 | **DEFERRED** — pass 2 rejected and reverted |
| 8 | F7 | — | DEFERRED at freeze |

P2 findings (F8, F9, F10, F11, R0-2..R0-11) are documented and **not fixed**, per the termination rules.

### Passes this run will and will not run

| pass | boundary | decision |
|---|---|---|
| 1 — Secrets and exposure | present (log, export) | **SKIPPED**: no frozen finding touches it. Secrets, network, and dependencies were all checked at Stage 0 and are recorded under NOT DEFECTS; the exposure findings (F8, R0-4) are P2. There is no authn/authz, no injection surface, and no request deserialization here, so those sub-passes do not exist rather than being reinterpreted. |
| 2 — Correctness (Swift 6) | present | **RAN, REVERTED.** F1's fix was rejected by Review 2 as a regression and reverted at `b582d94`; F1 is DEFERRED. |
| 3 — Data and persistence | present | **RUNS** — F6. Schema frozen: migration findings are described, never implemented. |
| 4 — Failure behavior | present | **RUNS** — F3, F4, F5, R0-1. |
| 5 — Observability | present | **RAN — F2 only.** The pass's brief also names import/export and cancellation verification as boundaries that must be observable; both are still unlogged at HEAD, because they are F11, a P2, and P2s are documented and not fixed. |
| 6 — Build and shippability | present | **SKIPPED**: no frozen finding touches it. Stage 0 verified no `#if DEBUG` behavior divergence on any shipping path and a clean-clone reproducible build. Release-on-device is prohibited this run and is recorded under CANNOT ASSESS. |
| 7 — Tests | — | **FOLDED INTO EACH PASS** rather than run separately, so every pass's diff is self-verifying and its reviewer sees the fix and its test together. Every test added is falsified — the fix is broken, the failure observed and recorded in the commit message, then restored. |

## NEXT ROUND

Findings discovered after the Review 0 freeze. **Not fixed in this run, regardless of severity.**

- **R0-6** — `reconstructWatermarksNow` leaves a resurrected-after-tombstone subscription with a nil watermark. Full evidence in the findings table and `reviews/REVIEW-0.md` §R0-6. F6's fix in pass 3 routes the empty-database case into this path, so closing R0-6 is the natural next step.
- **R0-7 (stored-data repair)** — F1's fix stops new corruption; every calendar day already written under a non-Gregorian device calendar stays wrong. A repair pass over stored days is a new user-visible capability and is therefore DEFERRED, but it is the other half of F1.
- **R0-5, R0-9, R0-10, R0-11** and the P2 findings F8, F9, F10, F11 — all documented above with full evidence.
- From `reviews/REVIEW-0.md` §4, two items recorded as unconfirmed rather than as findings, worth a deliberate look: `SyncActivationService` is constructed only in its own test and is wired into nothing, while `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` (`project.yml:72-73`) ship for it today; and `OttoMigrationPlan.swift:250-262` verifies the V2→V3 watermark carry-over by fetching from the context that just wrote it, which may verify the assignment rather than durability, immediately before a destructive column drop.

## Status

*(Per-finding status is filled in at the final stage.)*
