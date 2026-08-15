# REVIEW-0 — the Stage 0 ledger

**Verdict: PASS-WITH-FINDINGS**

Reviewed: `406a5a686d1c6b67d251ba38c36545ebbb772ff3..HEAD` on `prod-readiness/2026-08-10`.
The range is one commit, `447b173`, adding two files: `PROD-READINESS.md` and `reviews/BASELINE.md`.
No code changed, so there is no changed path to exercise; this review verifies the ledger's claims against the tree and hunts for what it missed.

Nothing in the ledger was struck.
Eleven added findings follow, one of them P1.
No severity in the ledger was changed.

---

## 1. Verification I re-ran myself

Every number below was produced by this review, not read from `BASELINE.md`.

| What | Command | Result | Matches BASELINE? |
|---|---|---|---|
| Host suite | `./scripts/verify.sh` | exit 0; OttoDomain 246, OttoPersistence 112, OttoUI 168, **total 526**; lint clean under `--strict` | ✅ exactly |
| Simulator suite | `xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"` | exit 0; `** TEST SUCCEEDED **`; **19 tests in 3 suites, 7 known issues**, all in `EmptyStateTests` label assertions | ✅ exactly |
| Source size | `find . -name '*.swift' -not -path './build/*'` | 203 files, 32,663 lines | ✅ ("203 files, ~32,700 lines") |
| Network absence | `grep -E "URLSession\|URLRequest\|NWConnection\|CFNetwork\|http://\|https://"` over all four source trees | zero hits in `Sources/`; the only hits anywhere are `example.com` fixtures in tests and two plist DOCTYPE URLs | ✅ |
| Secrets | key/token/password/private-key patterns over the tree and over `git log -p --all` | zero real hits (two comments containing the word "token") | ✅ |
| `try!` / `#if DEBUG` | grep over `Packages/*/Sources` and `Otto/` | zero `try!`; `#if DEBUG` only at `Previews.swift:1`, `PreviewSupport.swift:1` | ✅ |
| F1 calendar numbers | compiled Swift snippet, `Calendar(identifier:)` per calendar over the same instant | Gregorian 2026-08-06, Buddhist **2569**, Japanese **8**, Hebrew **5786-12-23**, Islamic **1448-02-23**; all four in `CalendarDay`'s valid range | ✅ exactly |

Prohibited-action check on the range: `406a5a6` is an ancestor of `HEAD` (no rewrite), no remote branch contains `HEAD` (not pushed), `git diff --name-status` over the range is two `A` lines for markdown files only.
No `.github/workflows/` change, no `Package.swift` change, no SwiftData schema change, no `<backup-dir>` access, no device access, no network call.
The working tree is clean after this review; the only file I wrote is this one.

---

## 2. Ledger findings — per-finding verification

I read every cited line at HEAD. **All eleven confirmed. None struck. No severity changed.**

| id | cited evidence | verified? | note |
|---|---|---|---|
| F1 | `DateProvider.swift:34`; `CalendarDay.swift:66-72`, `:44-57`, `:178`; `CalendarDayBinding.swift:7,16`; `DisplayFormatting.swift:33` | ✅ all six exact | measured numbers reproduce exactly; blast-radius sentence is wrong for half of them, see **R0-2**; fix is incomplete, see **R0-7**, **R0-8** |
| F2 | `NotificationCoordinator.swift:234`; `NotificationActionHandler.swift` has zero `OttoLog` | ✅ (`grep -c OttoLog` = 0) | `:150` is the throwing `client.add`, not the `.remindLater` case (that is `:96-104`); loose but not wrong. The ledger omits `.cancelling`, where a throw also suppresses the follow-up that opens the cancellation URL — strengthens, not weakens, the finding |
| F3 | `NotificationStatusStore.swift:43-47`; `TodayView.swift:187-193`; `NotificationCoordinator.swift:113-119`; `NotificationStatusStore.swift:7-9` | ✅ all exact | I also confirmed the finding is real and not masked: `TodaySection.plan` (`TodayView.swift:61-63`) gates the footer on permission only, never on outcome freshness |
| F4 | `NotificationActionHandler.swift:159`, `:148`, `:189-191`; `PlannedReminder.swift:45`; `NotificationScheduler.swift:345` | ✅ all exact | I checked the adjacent `categoryIdentifier: NotificationCategory.actionable` at `:160` for the same asymmetry: it is **correct**, because `remindLater` exists only on the `actionable` category (`LiveNotificationClient.swift:66-87`), so only `actionable` kinds can reach the snooze. P1 is at the upper edge of defensible given the UNVERIFIED tag, but the deadline-money argument carries it |
| F5 | `NotificationScheduler.swift:180-183`, `:279-281`; `NotificationCoordinator.swift:114`; `OttoLog.swift:91-95` | ✅ all exact | the "it is logged" claim is correct: the throw escapes `reconcile`'s own log line at `:188` but is caught and logged by the trigger wrapper at `OttoLog.swift:90-96`. `NotificationReconciliationTests.swift:76-106` already drives this path with `refuseAdds(after: 0)` and asserts only that pre-existing rungs survive — it does not assert that the not-yet-added rungs are lost, so the defect is live under a green test |
| F6 | `SettingsView.swift:293-294`; `ExportService.swift:78-81`; `OttoStore+BillingEvents.swift:53-54` | ✅ all exact | CONTAMINATED tag is honest; the fix's destination path has holes, see **R0-6** |
| F7 | `ImportResolution.swift:161` | ✅ exact | correctly DEFERRED |
| F8 | `SettingsView.swift:185`, `:201-208`; `ExportService.swift:87-91` | ✅ all exact | filename is `Otto-Export-<day>.json` (`ExportService.swift:37,44`), so "one dated pair per day" is right. The `tmp`-is-not-backed-up mitigation is the right reason for P2 |
| F9 | `ChargesCSV.swift:64-69` | ✅ exact | names do reach `csvField` (`ChargesCSV.swift:34`). "There is no untrusted input path" is slightly overstated — JSON import is an input path — but with one user importing their own export, P2 is unaffected |
| F10 | `NotificationCoordinator.swift:112-120`, `:94,:99,:108,:220,:245`; `NotificationScheduler.swift:76,93,127,130,137` | ⚠️ partially | five call sites cited for "six triggers"; `:76` is not a suspension point (`:75` is) and the list omits `:94`, `:116`, `:117`. See **R0-3**. The substance — unstructured `Task` per trigger, no coalescing, interleaving passes — is correct |
| F11 | `OttoLog.swift:27-31`; absence of `OttoLog` in `ExportService.swift`, `SubscriptionFlowService.swift`, `NotificationActionHandler.swift` | ✅ (`grep -c` = 0 in all three) | phrased at file level rather than line level for the three gaps, which is the weakest compliance with "every finding cites a specific line" in the ledger; the underlying fact is verified. The premise "`OttoLog` defines exactly two categories" is true of the enum but there is a third `Logger` outside it — see **R0-4** |
| PD1 | `verify.sh` is at `scripts/`, not the root | ✅ | |
| PD2 | `verify.sh` prints `docs/next-wave.md` in full | ✅ substance | the citation `scripts/verify.sh:108-125` is out of range — the file is 118 lines and the print is at `:117-118`. See **R0-3**. I confirmed the contamination independently: my own `verify.sh` run printed the whole `⛔ RESUME HERE` section including both named defects |
| PD3 | the prompt's "fake whose `add` never throws" hazard is stale | ✅ | confirmed: `TestSupport.swift:106-163` has `refuseAdds(after:)` and `AddRefused`; `LiveNotificationClientTests.swift:144-149` asserts `add` propagates. The other named hazard is also closed: `NotificationReconciliationTests.swift:131-140` now asserts the full sentence and `!body.contains("CA$")` |

**Fabricated or unreproducible findings: none.**
Every finding names a real line that says what the ledger says it says, with the citation exceptions logged as R0-3.

**Severity inflation or deflation: none I will act on.**
The ledger assigns no P0 at all, which under "be stingy with P0" plus "when severity is ambiguous, assign the lower one and say why" is defensible: each candidate is gated (F1 on a device setting, F5 on `add` throwing, F2/F3 on a throw that is at least partly logged), and the ledger states the gate in each case.
`ASSUMPTIONS 1` in particular does the right thing: it names the assumption, assigns P1, and says F1 becomes P0 unconditionally in a non-Gregorian-default region.

**Features smuggled in: none.** The commit adds two markdown files.
**SwiftData schema change: none.** `OttoMigrationPlan.schemas` is `[V1, V2, V3]` and `OttoContainerFactory.mainSchema` is `Schema(versionedSchema: OttoSchemaV3.self)`, both untouched.
**Marked resolved without an artifact: none.** The Status and NEXT ROUND sections are correctly left empty for later stages.

---

## 3. Added findings

These are mine, verified at HEAD, none of them in the ledger.

### R0-1 — `ledgerFailures` reaches no user-facing surface, so Today asserts coverage for subscriptions that have none

**severity: P1**

**evidence.**
`ScheduleOutcome.swift:18-21` declares `ledgerFailures` with the comment *"scheduling continued without them rather than aborting, but the failure is not swallowed."*
`grep -rn ledgerFailures` over the whole repo returns exactly four production references: the declaration, the initializer, `NotificationScheduler.swift:94` and `:144` that populate it, and `OttoLog.swift:87` which logs `ledgerFailures.count`.
Plus one test, `PhoneInADrawerTests.swift:83`.
**Nothing in `OttoUI/` reads it.**
Meanwhile the pass that produced it returns normally, so `ScheduleOutcome.coveredThrough` is `horizonEnd` (`NotificationScheduler.swift:139-145`), `NotificationStatusStore.apply(_:)` publishes it (`:52-55`), and `TodayView.swift:187-193` renders `"Reminders scheduled through \(coveredThrough)."`
`TodaySection.plan` gates that footer on `hasScheduleOutcome` and permission only (`TodayView.swift:61-63, 113`), never on `ledgerFailures.isEmpty`.
A subscription whose `materializeEvents` threw has no billing rows this pass, therefore no reminders, and the screen whose entire job is honest coverage says its reminders are scheduled for the next ninety days.

**why the builder missed it.**
F3 framed the honesty problem as *stale outcome after a failed pass*, and stopped there.
This is the opposite shape: a **fresh, successful** outcome that is itself an overstatement.
F3's proposed fix — clear or invalidate `outcome` when a pass fails — does not close it, because this pass does not fail.
The ledger read `reconcileLedger`'s per-subscription tolerance at `NotificationScheduler.swift:279-281` while writing F5's fix column and treated it as the good example to copy, without asking where the resulting failure list goes.

### R0-2 — F1's blast radius is contradicted by two of the four calendars F1 itself measured

**severity: P2** (a defect in the ledger's claim, not a change to F1's P1)

**evidence.**
The ledger states the consequence as *"reminders are simply scheduled centuries away and never fire."*
That is true for Buddhist (2569) and Hebrew (5786) but false for Japanese (8) and Islamic (1448), which are **in the past**.
Reproduced by compiled snippet, same instant, `America/Toronto`:

```
buddhist:          y=2569 fireDate=2569-08-06 past=false
japanese:          y=8    fireDate=0008-08-06 past=true
hebrew:            y=5786 fireDate=5786-12-23 past=false
islamicUmmAlQura:  y=1448 fireDate=1448-02-23 past=true
republicOfChina:   y=115  fireDate=0115-08-06 past=true
persian:           y=1405 fireDate=1405-05-15 past=true
```

A past fire instant does not take the silent branch.
`NotificationScheduler.swift:334` tests `if fireDate > now`; a past instant falls to `:348`, `else if !delivered.contains(identifier)`, which emits a spec with `catchUpIntervalSeconds: Self.catchUpIntervalSeconds` (`:360`) — a five-second interval trigger (`:23`).
So on a Japanese-, Islamic-, ROC- or Persian-calendar device the failure is not silence; it is up to sixty-four notifications firing about five seconds after **every** scheduling pass, and again after each pass once the user clears them, because the delivered check reads Notification Center.
Both modes are total breakage, so F1 stays P1 — but the ledger states one mechanism where the code has two, and it is the *measured* half of its own evidence that contradicts it.

**why the builder missed it.**
The year numbers were computed at the `DateProvider` boundary and reasoned about there.
They were never carried forward through `requestSpecs`' past-instant branch, which is the code Wave 10 added specifically to stop dropping passed-instant rungs.

### R0-3 — four out-of-range or wrong line citations, and one count that does not match its citation list

**severity: P2**

**evidence.**

- `PROD-READINESS.md:36` cites `project.yml:56-57` for `BGTaskSchedulerPermittedIdentifiers`. Those lines are `path: Otto/App/Info.plist` and `properties:`. The declaration is at `project.yml:67-68`.
- `PROD-READINESS.md:29` cites `project.yml:71` for `aps-environment: development`. Line 71 is a comment, `# user can find it is a plist setting, not just a directory choice.` The entitlement is at `project.yml:80`.
- `PROD-READINESS.md:79` (PD2) and `BASELINE.md:53` cite `scripts/verify.sh:108-125`. `wc -l` on that file is **118**. The `docs/next-wave.md` print is at `:117-118`.
- F10 cites `NotificationScheduler.swift:76` as a suspension point. `:76` is `let horizonEnd = today.adding(days: Self.horizonDays)`, a pure computation; the `await` is at `:75`. The list also omits three real suspension points in the same function: `:94`, `:116`, `:117`.
- F10 says "six triggers can overlap" and then cites five call sites (`:94, :99, :108, :220, :245`). There are five `rescheduleSoon` sites; the sixth and seventh concurrent entry points are the background `Task` at `NotificationCoordinator.swift:152` and `NotificationStatusStore.reschedule()`, neither of which is cited.

**why the builder missed it.**
These sit in the Context and prompt-defect sections rather than the findings table, so they were not re-read against HEAD the way the findings' evidence was.
The `:76`-for-`:75` slip is the one that matters: it is inside a finding, and a reviewer checking F10 by opening `:76` would find a pure expression and reasonably conclude the finding was invented.

### R0-4 — the "no amount or vendor detail reaches `os_log`" NOT-DEFECT is refuted; there is a third `Logger` the audit never saw

**severity: P2**

**evidence.**
`PROD-READINESS.md:107` claims *"no amount, vendor name, or card detail reaches `os_log` on any path. Audited directly against every call site."*
`OttoStore.swift:8` declares a logger outside `OttoLog` entirely:

```swift
let mappingLogger = Logger(subsystem: "com.arthurzhang.otto", category: "persistence")
```

`OttoStore.swift:118-125` logs the whole error on every unmappable record read:

```swift
mappingLogger.error("Skipping unmappable record: \(String(describing: error))")
```

`MappingError` is `CustomStringConvertible` and its `.invalidValue` case interpolates a `value` (`MappingError.swift:18, 24`).
Two of the call sites put user financial content in that slot:

- `SubscriptionMapping.swift:153-159` throws `value: "\(lengthDays)/\(bufferDays)/\(convertsTo)"`, where `convertsTo` is `convertsToAmountCents` — **an amount**.
- `StorageShapes.swift:53-58` (`URL.storedOptional`) throws `value: value`, the raw URL string, reached for `vendorURL` (`SubscriptionMapping.swift:43`) and `cancellationURL` (`:55`) — **which vendor**.

Mitigating, and the reason this is P2 rather than higher: `Logger` string interpolation defaults to `.private`, so these are redacted on read without a private-data profile.
That is the same shape of mitigation F8 leans on for `tmp`.
But `OttoLog.swift:19-21` states this project's own doctrine on exactly that mitigation: *"Anything richer must stay out, not merely be marked private: `.private` redaction is a display rule, not a guarantee about what was written."*
By the ledger's own standard the claim at `:107` is false as written.

**why the builder missed it.**
Both the NOT-DEFECT audit and F11's premise scope themselves to the `OttoLog` enum.
No grep for `Logger(` outside that file was run, so an entire third category — `persistence`, in the layer that holds the money — was invisible to both.

### R0-5 — a corrupt stored watermark silently becomes "no watermark", reproducing F6's failure signature by a second route

**severity: P2**

**evidence.**
`OttoStore.swift:69-77`:

```swift
return rows.first?.lastMaterializedThrough.flatMap(CalendarDay.init(yyyymmdd:))
```

`CalendarDay.init?(yyyymmdd:)` returns nil for an impossible packed date (`StorageShapes.swift:17-19`), and `flatMap` turns that nil into the same nil an **absent row** produces.
The caller cannot tell "no watermark was ever written" from "the watermark is corrupt".
`OttoStore+BillingEvents.swift:53-54` then does `min(storedWatermark ?? today, today)` and materializes from today — the identical outcome F6 describes, and the exact signature `BASELINE.md:174` calls "the v2.1 failure signature and a FAIL".
Neither path logs anything.
Separately, `rows.first` runs on an unsorted fetch with no `sortBy`; the schema deliberately carries no `@Attribute(.unique)` for CloudKit compatibility, so if two rows ever exist for one subscription the value picked is nondeterministic.

**why the builder missed it.**
F6 arrived pre-disclosed with a specific citation (`BASELINE.md:59`).
The run confirmed that citation rather than asking the general question the citation implies: what else makes this watermark nil?

### R0-6 — F6's proposed fix routes the recovery case into a reconstruct path with its own nil-watermark holes

**severity: P2**

**evidence.**
F6's fix is *"Decouple the watermark policy from the merge strategy, or reconstruct whenever the database was empty."*
The destination is `reconstructWatermarksNow` (`OttoStore+DataTransfer.swift:202-238`), which the ledger never reads.
`:214-221` deletes **every** watermark row unconditionally, inside the loop:

```swift
for row in rows {
    if let id = row.subscriptionID, let stored = row.lastMaterializedThrough { ... }
    deviceStateContext.delete(row)
}
```

`:222-231` re-creates a row only for a subscription that survives three filters: the fetch at `:203-205` excludes tombstoned subscriptions, and `:223-225` requires a non-nil `id` and a non-nil `latestBySubscription[id] ?? cycleStartDay`, otherwise `continue` leaves no row at all.
So a subscription that is tombstoned at reconstruct time and later resurrected — which a merge import can do, `ImportResolution.swift:161-168` — comes back with a nil watermark and materializes from today.
The whole thing is one atomic save (`:235-237`), so there is no torn state; the hole is in what is rebuilt, not in when.

**why the builder missed it.**
The ledger stopped at the strategy-to-policy mapping (`ExportService.swift:78-81`), which is where the disclosed defect lives.
Proposing to send the empty-database case down `.reconstruct` requires reading `.reconstruct`, and that read did not happen.

### R0-7 — F1's fix stops new corruption but repairs nothing already stored, and the ledger does not say so

**severity: P2**

**evidence.**
Calendar days reach the database as packed `yyyymmdd` integers (`StorageShapes.swift:22-30`), written from whatever `CalendarDay` the boundary produced.
F1's fix column reads *"Pin an explicit Gregorian calendar (device time zone preserved) at all three boundaries. No schema change, no new API."*
Pinning `DateProvider.swift:34`, `CalendarDayBinding.swift:7,16` and `DisplayFormatting.swift:33` changes only values created after the fix.
On a device that has been running with a non-Gregorian calendar, every stored billing anchor, trial start, cancel-by date and ledger row is already a wrong number, and after the fix those numbers are read back as proleptic Gregorian and are still wrong.
This is a fix that relocates the boundary rather than removing the damage.
A repair pass over stored days is a new capability, so under the scope constraint it is **DEFERRED** — but the ledger must record it, because as written F1 reads as a complete fix.

**why the builder missed it.**
F1 was reasoned about at the boundary where the bad value enters, not over the data already behind it.

### R0-8 — F1 says "all three boundaries"; there is a fourth site with the same defect

**severity: P2**

**evidence.**
`InsightsView.swift:137-145`:

```swift
var components = DateComponents()
components.year = month.year
components.month = month.month
components.day = 1
guard let date = Calendar.current.date(from: components) else {
    return "\(month.year)-\(month.month)"
}
return date.formatted(.dateTime.month(.wide).year())
```

`month` is a domain `MonthlyProjection`, so `year`/`month` are proleptic-Gregorian numbers being resolved through the device calendar — structurally identical to `DisplayFormatting.swift:33`.
On a Buddhist-calendar device the twelve-month spend projection is labelled 543 years off.
For completeness I checked the other `Calendar.current` sites in the view layer and they are **not** defects: `SettingsView.swift:85` and `:93` round-trip only hour and minute, which every calendar divides identically, so the notification-time setting is calendar-independent.

**why the builder missed it.**
The F1 sweep covered the store and display seam files and did not extend into the view layer, where one more view builds a `Date` from domain integers.

### R0-9 — the migration guard cannot detect a missing stage, in a file that claims to be structurally unable to go stale

**severity: P2**

**evidence.**
`CloudKitCompatibilityTests.swift:5-8` describes the hazard it was hardened against: *"It spent Wave 6A green while asserting `OttoSchemaV2` after V3 became real - a guard pinned to a version number stops guarding without ever failing."*
The hardened test, `:26-38`, asserts:

```swift
let live = OttoContainerFactory.mainSchema
let terminal = try #require(OttoMigrationPlan.schemas.last)
#expect(live.version == terminal.versionIdentifier)
```

plus entity-name and count equality.
It relates the factory to `schemas`.
It never relates `stages` to `schemas`, and `OttoMigrationPlan.swift:13-19` keeps them as two independent literals:

```swift
static var schemas: [any VersionedSchema.Type] { [OttoSchemaV1.self, OttoSchemaV2.self, OttoSchemaV3.self] }
static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }
```

Append `OttoSchemaV4` to `schemas` and point `mainSchema` at it without adding a stage, and this suite stays green — `schemas.last` and `mainSchema` still agree — while the carry-over that moves user data from V3 does not exist.
That is the file's own named hazard in its next incarnation.
No user impact today; it is a guard gap that matters at exactly the moment the CloudKit wave changes the schema.
Closing it is a test change, not a schema change, so it is in scope.

**why the builder missed it.**
The ledger recorded "staged migration plan pinned at V3" as a verified boundary fact (`PROD-READINESS.md:34`) and moved on.
It confirmed *where* the schema is pinned without asking whether the guard over it guards.
Given the review contract names "a schema guard stayed green while asserting a version that no longer existed" as a live hazard for this repository, this one deserved a look.

### R0-10 — two more silent paths in export/import, adjacent to F8 and F11

**severity: P2**

**evidence.**

(a) `SettingsView.swift:235-239` handles only the success half of the file picker:

```swift
.fileImporter(isPresented: $isPicking, allowedContentTypes: [.json]) { result in
    if case .success(let url) = result {
        Task { await preview(url) }
    }
}
```

There is no `.failure` branch, no log, and no alert, although the `failure` state and the "Nothing was imported" alert already exist at `:275-285` and are reachable from every other import path.
Stated honestly: iOS also delivers a user cancellation as `.failure`, so alerting unconditionally would be wrong — but with no logging on this path either (F11), a genuine read error on the recovery path and a cancel are indistinguishable afterwards.
This strengthens F11's fix rather than standing alone.

(b) `SettingsView.swift:22-23` puts `ExportSection` and `ImportSection` as siblings in one `List`; `:185` runs `.task { await regenerate() }` once, when `ExportSection` appears.
An import in the same Settings visit does not re-run it, and `ExportService.write` uses a stable per-day filename (`ExportService.swift:37, 44, 87-91`), so `ShareLink(item: jsonURL)` at `:165-169` hands out the **pre-import** file under a footer at `:179-183` calling it "the complete backup — every subscription, charge, and price change".
F8's proposed fix (generate on demand rather than on appearance) closes this too, and the ledger should record that it does.

**why the builder missed it.**
F8 examined `regenerate()` for *when it writes* and did not ask *when it is stale*; F11 established that import/export has no logging without walking the import entry point for what that absence hides.

### R0-11 — `invalidateOutdatedUpcomingEvents` can leave soft-deletes uncommitted and report "nothing invalidated"

**severity: P2**

**evidence.**
`OttoStore+BillingEvents.swift:176-184`:

```swift
record.deletedAt = instant
record.updatedAt = instant
if let event = try? record.toDomain() {
    invalidated.append(event)
}
...
if !invalidated.isEmpty {
    try modelContext.save()
}
```

The tombstone at `:176-177` is unconditional; the append at `:178` is guarded by `try?`; the save at `:182-183` is conditional on the append having happened at least once.
If every candidate that reaches `:176` then fails `toDomain()`, the method returns `[]` — reporting that nothing was invalidated — while the shared `modelContext` holds uncommitted soft-deletes that the next unrelated `save()` commits (for example `OttoStore+Subscriptions.swift:20`, or `OttoStore+Reconciliation.swift:18-19`) or that process exit discards.
The write escapes the decision that made it.
Narrow: it needs a record that has `expectedDate`, a valid packed day and `expectedAmountCents` but a nil `id`, `subscriptionID`, `createdAt`, `updatedAt` or `state` (`BillingEventMapping.swift:10-19`) — the partially-synced shape the file's own comments anticipate for Wave 6B.

**why the builder missed it.**
The persistence pass followed F6's disclosed citation into `materializeEvents` and did not sweep the sibling ledger-write path in the same file.

---

## 4. Accuracy notes that are not findings

- `PROD-READINESS.md:37` lists "pre-sync backup to Documents (`SyncActivationService.swift:60`)" among boundaries that are **present**. The line citation is exact, but `grep -rn SyncActivationService` over the whole repo shows the type is constructed only in `SyncActivationServiceTests.swift:60`. It is wired into nothing: `OttoApp.swift` never mentions it. No file is ever written to Documents today. A consequence worth carrying forward: `UIFileSharingEnabled: true` and `LSSupportsOpeningDocumentsInPlace: true` (`project.yml:72-73`) currently ship for a feature that does not exist.
- `PROD-READINESS.md:14` says "all 93 commits of history". `git rev-list --count HEAD` is 94 at HEAD and 93 at `406a5a6`, so the number was correct when written. Not a defect.
- `NotificationScheduler.swift:86-90` returns `coveredThrough: horizonEnd` on the permission-denied path while `scheduledCount` is 0 and every planned request was just removed. I checked whether this is rendered: it is not, because `TodaySection.plan` (`TodayView.swift:61-63`) drops the coverage section for any permission other than authorized or provisional. The value is false but currently unreachable, so I am not filing it. It becomes a real finding the moment that gate changes, and F3's fix touches that area.
- `OttoMigrationPlan.swift:250-262` verifies the V2→V3 watermark carry-over by fetching from the same `ModelContext` that just wrote it, immediately after `save()`. This may verify the assignment rather than durability on disk. I did not build a harness to prove it either way, so I am recording it as unconfirmed rather than as a finding. It is the sole gate before a destructive column drop and is worth a deliberate look during the CloudKit wave.

---

## 5. What this verdict means for the next stage

The ledger is sound: every finding it makes is real, cites a line that says what it claims, and proposes a fix that stays within the scope constraint and the V3 schema freeze.
It is not complete, and its Context section's citations were not held to the same standard as its findings' citations.

Work may proceed.
Before it does, the following should be folded into the ledger:

- **R0-1** joins the findings table at **P1**.
- **R0-2**, **R0-7** and **R0-8** amend F1 (blast radius, fix completeness, a fourth site); the stored-data repair in R0-7 goes to **DEFERRED** with the reason stated.
- **R0-6** amends F6's fix column.
- **R0-10(b)** amends F8's fix column; **R0-10(a)** amends F11's.
- **R0-3** corrects five citations.
- **R0-4** strikes the second half of the NOT-DEFECT at `PROD-READINESS.md:107` and adds the `persistence` logger to F11's premise.
- **R0-5**, **R0-9** and **R0-11** join the findings table at **P2**.

`BASELINE.md` needs no correction: both of its headline numbers reproduce exactly on this host, and its contamination disclosure is accurate — running the mandated command did disclose the forbidden list, and I saw the same output.
