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

**How it ships.** Sideloaded development build, signed with `DEVELOPMENT_TEAM: <team-id>`, `CODE_SIGN_STYLE: Automatic`, bundle id `com.arthurzhang.otto`, installed on one physical iPhone. `aps-environment: development` (`project.yml:71`). To ship it to anyone else would require: a distribution signing identity, a non-development APS environment, a provisioned CloudKit container if sync is ever enabled, and TestFlight or ad-hoc provisioning per device. None of that exists today and none of it is in scope here.

**Boundaries — both lists verified, not accepted.**

Present, as the prompt predicted:
- Local persistence — SwiftData over SQLite, two containers (`OttoContainerFactory.swift:63-78`), staged migration plan pinned at V3.
- Notifications — `UNUserNotificationCenter` behind the `UserNotificationCentering` seam (`LiveNotificationClient.swift:19-27`).
- Background execution — `BGTaskScheduler`, identifier `com.arthurzhang.otto.refresh` (`NotificationCoordinator.swift:21`, `project.yml:56-57`).
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
| F1 | date/calendar | P1 | INDEPENDENT | `OttoStores/DateProvider.swift:34` reads `Calendar.current.dateComponents([.year,.month,.day])` and feeds the result straight into `CalendarDay`, whose arithmetic is **proleptic Gregorian by construction** (`OttoDomain/Models/CalendarDay.swift:66-72`, `:44-57`) and whose only instant conversion hard-codes `Calendar(identifier: .gregorian)` (`:178`). Same defect at `OttoUI/CalendarDayBinding.swift:7,16` and `OttoStores/DisplayFormatting.swift:33`. | Pin an explicit Gregorian calendar (device time zone preserved) at all three boundaries. No schema change, no new API. | Total and silent for any device whose calendar is not Gregorian: every billing date, every reminder day, every fire instant. Measured: Buddhist yields year **2569**, Japanese **8**, Hebrew **5786-12-23**, Islamic **1448-02-23** for the same instant Gregorian calls 2026-08-06. `CalendarDay(year: 2569, …)` is *valid*, so nothing throws — reminders are simply scheduled centuries away and never fire. Zero for a Gregorian device. |
| F2 | notifications / error handling | P1 | INDEPENDENT | `OttoServices/NotificationCoordinator.swift:234` — `let followUp = try? await handler.handle(…)`. `NotificationActionHandler.swift` contains **no logging at all** (verified: `OttoLog` appears nowhere in that file). | Log the failure on `OttoLog`; do not discard it. Surfacing to the UI is a separate, deferred question. | The user's answer to a notification is destroyed with no trace. "Remind me later" is the terminal case: `snooze` (`NotificationActionHandler.swift:150`) is the *only* thing that action does, the system has already consumed the notification, and a throw there means the reminder simply ceases to exist. "Yes — it stopped" and "Keeping it" partially self-heal on a later pass; the snooze does not. |
| F3 | notifications / honesty | P1 | INDEPENDENT | `OttoStores/NotificationStatusStore.swift:43-47` — the `catch` refreshes `permission` and leaves `outcome` untouched. `OttoUI/TodayView.swift:187-193` renders `"Reminders scheduled through \(coveredThrough)."` from that stale `outcome`. Compounded by `NotificationCoordinator.swift:113-119`, where `rescheduleSoon` swallows with `try?` and so never calls `onOutcome` on a failed pass. | Clear or invalidate `outcome` when a pass fails, so Today stops asserting coverage it no longer has. | Today keeps stating a coverage date derived from the last *successful* pass, indefinitely. The screen whose stated job is "never fail silently when it cannot send" (`NotificationStatusStore.swift:7-9`) is exactly where the false reassurance appears. |
| F4 | notifications / Focus | P1 | INDEPENDENT | `OttoServices/NotificationActionHandler.swift:159` hard-codes `isTimeSensitive: false` for every snooze, while the kind is carried through faithfully (`:148`, `:189-191`) and `.trialDayOfMorning` / `.trialDayOfEvening` are time-sensitive in the plan (`OttoDomain/Scheduling/PlannedReminder.swift:45`). | Derive `isTimeSensitive` from `kind.isTimeSensitive`, as the scheduler already does at `NotificationScheduler.swift:345`. | Snoozing the cancel-by-day warning silently downgrades it out of Focus breakthrough. The user asks to be reminded later about the one deadline that costs unrecoverable money, and the later reminder is the one that can be held by a Focus mode or Scheduled Summary. **UNVERIFIED on hardware** — Focus behavior is not observable in the simulator. |
| F5 | notifications / partial failure | P1 | INDEPENDENT | `OttoServices/NotificationScheduler.swift:180-183` — `for spec in specs where … { try await client.add(spec) }`. The first throw aborts the loop; every remaining rung is never added. The throw reaches `rescheduleSoon`'s `try?` (`NotificationCoordinator.swift:114`). | Collect per-spec failures and continue, mirroring `reconcileLedger`'s existing per-subscription tolerance (`NotificationScheduler.swift:279-281`); report them in `ScheduleOutcome`. | One rejected `add` silences every rung ordered after it. The pass *is* logged (`OttoLog.swift:91-95`), so it is diagnosable — but the user sees F3's stale coverage line and no error. Ordering is deterministic, so the same rungs lose every pass. |
| F6 | data / restore | P1 | **CONTAMINATED** | `OttoUI/SettingsView.swift:293-294` — an empty database takes `.merge` with no prompt; `.merge` maps to `watermarks: .keep` (`OttoServices/ExportService.swift:78-81`); a nil watermark makes materialization start from today (`OttoPersistence/Store/OttoStore+BillingEvents.swift:53-54`). | Decouple the watermark policy from the merge strategy, or reconstruct whenever the database was empty. | The empty database **is** the recovery case — restore after reinstall — so the default path is the wrong one. Confirmed independently by reading the cited lines; disclosed to this run beforehand, so it is not evidence about this sweep's reach. |
| F7 | data / clock | P1 | **CONTAMINATED** | Merge resolution orders on `updatedAt` (`OttoDomain/Export/ImportResolution.swift:161`) and the device clock is not monotonic. | Described only. | Recorded for completeness. Full prior analysis lives in `docs/sync-safety.md`; this run adds nothing to it and does not fix it. |
| F8 | export / exposure | P2 | INDEPENDENT | `OttoUI/SettingsView.swift:185` — `.task { await regenerate() }` writes **both** exports on every appearance of the Settings screen (`:201-208`), unrequested, to `FileManager.default.temporaryDirectory` with no protection class specified (`OttoServices/ExportService.swift:87-91`). | Generate on demand rather than on appearance. | A complete unencrypted financial record — every vendor, amount, and the payment method's last four — is written to disk merely by visiting Settings, and accumulates one dated pair per day. Mitigating: `tmp` is excluded from iCloud/iTunes backup and is not reachable by other apps on a non-jailbroken device, and the default protection class still requires first unlock. That mitigation is why this is P2 and not higher. |
| F9 | export / correctness | P2 | INDEPENDENT | `OttoDomain/Export/ChargesCSV.swift:64-69` — `csvField` implements RFC 4180 quoting only; it does not neutralize a leading `=`, `+`, `-`, or `@`. | Prefix at-risk fields. | A subscription the user named `=1+1` or `=HYPERLINK(…)` becomes a live formula when the CSV is opened in Numbers or Excel. Self-inflicted only — the user types their own vendor names, there is no untrusted input path — which is why this is P2. |
| F10 | concurrency | P2 | **CONTAMINATED** | `OttoServices/NotificationCoordinator.swift:112-120` — `rescheduleSoon` spawns an unstructured `Task` per trigger with no coalescing; six triggers can overlap (`:94`, `:99`, `:108`, `:220`, `:245`). `NotificationScheduler.reschedule` is actor-isolated but suspends at `:76`, `:93`, `:127`, `:130`, `:137`, so passes interleave. | Serialize or coalesce passes. | Bounded, not zero: `OttoStore` is a `@ModelActor` and `materializeEvents` runs without suspension, so no duplicate ledger rows. The exposed window is a stale pass computing `stale` from a `pending` snapshot older than a concurrent pass's adds. Adds are idempotent replaces and removes never touch a desired rung, so the sets converge on the next pass. **UNVERIFIED** — not reproduced. |
| F11 | observability | P2 | INDEPENDENT | `OttoLog` defines exactly two categories, `background` and `scheduling` (`OttoServices/OttoLog.swift:27-31`). Verified by grep: there is no logging on **import/export** (`ExportService.swift`), on **cancellation or verification** (`SubscriptionFlowService.swift`), or on **notification actions** (`NotificationActionHandler.swift`). | Add boundary logging to those three paths. | Pass 5 of this run's own brief names "import/export" and "cancellation verification" as boundaries that must be observable. They are not. After a restore that went wrong while nobody was watching, the device holds no record that a restore was even attempted. |

### Prompt defects found (reported, not fixed)

| id | evidence | why it matters |
|---|---|---|
| PD1 | The prompt states "This project has `verify.sh` at the repo root". It is at `scripts/verify.sh`. | Trivial, but it is the file every other claim in the run is measured against. |
| PD2 | Stage 0 forbids reading the project's defect lists; Stage 0 mandates running `verify.sh`; `verify.sh` prints `docs/next-wave.md` in full (`scripts/verify.sh:108-125`), which **is** that defect list. | The two instructions cannot both be obeyed. This destroyed the "most informative output of this entire run" before the first finding was written. Fully disclosed in `reviews/BASELINE.md`; findings tagged CONTAMINATED accordingly. |
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
- **The logging that exists is privacy-clean.** `OttoLog` marks only opaque UUIDs, calendar days, and control-flow outcomes as `.public` (`OttoLog.swift:14-21`); no amount, vendor name, or card detail reaches `os_log` on any path. Audited directly against every call site.

## DEFERRED

- **F7** (clock monotonicity in merge resolution) — prior analysis exists in `docs/sync-safety.md` and it is scoped to the CloudKit wave.
- Anything requiring a **SwiftData schema change**: none of F1–F11 does. The schema is untouched by every fix proposed above.

## NEXT ROUND

*(Populated after Review 0 freezes the work list. Findings discovered after that point are appended here, not fixed.)*

## Status

*(Per-finding status is filled in at the final stage.)*
