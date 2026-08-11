# REVIEW-1 — stage 1 (F1, the calendar defect at both ends), commit range `7a3cf54..a82d4e0`

**VERDICT: PASS-WITH-FINDINGS**

The code change is correct, complete at the five sites it names, behavior-preserving on a Gregorian device, and verified by me on four non-Gregorian environments including real iOS on the Simulator.
Every falsification the commit message describes reproduces, the guards fail for the defect they name rather than for a proxy, and the round-1 objections this stage answers (`reviews/REVIEW-2.md` findings 1, 4, 5, 6) are all genuinely closed.
The findings below are about **guard coverage on two of the five changed sites** and about **four claims in the record that overstate what the commands actually printed**.
None of them is a reason to revert; all of them are reasons the record cannot be read at face value.

---

## Verification re-derived from scratch (nothing below is taken from an artifact)

| measurement | `reviews-2/BASELINE-2.md` at `7a3cf54` | re-derived by me at `7a3cf54` | re-derived by me at `a82d4e0` |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 533 (246 / 113 / 174) | OttoDomain **246**, OttoUI **174** (rebuilt from a fresh clone of `7a3cf54`) | **exit 0**; OttoDomain **248**, OttoPersistence **113**, OttoUI **178**, total **539** |
| `swiftlint --strict` | clean | - | **clean** (inside `verify.sh`) |
| simulator suite from `Packages/OttoUI/` | `** TEST SUCCEEDED **`, 101 / 65 / 20, 7 known issues | - | **`** TEST SUCCEEDED **`**, **102 / 68 / 20**, **7 known issues**, exit 0 |

Deltas are exactly the six tests the diff adds: OttoDomain +2, OttoUI +4 (host), simulator +1 / +3.
The seven known issues are the same four `EmptyStateTests` accessibility assertions; nothing regressed.

Commands, verbatim:

```
bash scripts/verify.sh                                    # exit 0
cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package \
  -destination "id=<simulator-udid>"  # ** TEST SUCCEEDED **
```

### The non-Gregorian environment claim is true, and I reproduced it four ways

`reviews-2/BASELINE-2.md:43-64` overturns round 1's "unverifiable on this host by construction" (`PROD-READINESS.md:133`).
That overturning is correct.
I ran the committed bundles under three locale overrides on the host and once on the Simulator:

| environment | OttoDomain @ `a82d4e0` | OttoUI @ `a82d4e0` |
|---|---|---|
| host default `en_CA` (gregorian) | 248 passed | 178 passed |
| `-AppleLocale th_TH@calendar=buddhist` | 248 passed | 178 run, **1 issue** (pre-existing, see finding 4) |
| `-AppleLocale ar_SA@calendar=islamic-umalqura` | 248 passed | 178 run, **5 issues** (all pre-existing, see finding 4) |
| `-AppleLocale ja_JP@calendar=japanese` | - | 178 run, **1 issue** (pre-existing) |
| Simulator `-testLanguage th -testRegion TH` | - | all four F1 guards **passed**; run ended `** TEST FAILED **` (finding 4) |

The Simulator run is genuinely Buddhist: `DisplayFormattingTests.swift:49` renders `"Aug 15, 2569 BE"` there, which only a Buddhist `Calendar.current` produces.
So the F1 guards passing in that run is real evidence about real iOS `UserNotifications` trigger resolution, which is the single most important thing this stage needed to show.

### Falsification re-performed independently

In a scratch clone outside the repository, `git checkout 7a3cf54 -- <the five source files>` with the new tests kept:

```
=== five sources reverted, GREGORIAN host ===
✘ "⛔ the trigger NAMES the Gregorian era…" LiveNotificationClientTests.swift:145:9:
   (trigger.dateComponents.calendar?.identifier → nil) == (.gregorian → gregorian)
✘ Test run with 178 tests in 31 suites failed … with 1 issue.

=== five sources reverted, BUDDHIST host ===
✘ CalendarEraTests.swift:45:9   DateProvider.live … (observed == before → false) || (observed == after → false)
✘ CalendarEraTests.swift:53:9   (day.displayDate() → 1483-08-15 05:17:32 +0000) == (… → 2026-08-15 04:00:00 +0000)
✘ CalendarEraTests.swift:70:9   ("Aug 15, 2026 BE") == ("Aug 15, 2569 BE")
✘ LiveNotificationClientTests.swift:145:9  calendar?.identifier → nil
✘ LiveNotificationClientTests.swift:146:9  (trigger.nextTriggerDate() → nil) == (… → 2026-09-10 13:00:00 +0000)
✘ DisplayFormattingTests.swift:49:9        (pre-existing, unrelated)
✘ Test run with 178 tests in 31 suites failed … with 6 issues.
```

Removing only `calendar.timeZone = .autoupdatingCurrent` from `CalendarDay.swift:171`, Gregorian host:

```
✘ "its timezone autoupdates…" CalendarDayTests.swift:19:9:
   (CalendarDay.conversionCalendar.timeZone → America/Toronto) == (TimeZone.autoupdatingCurrent → autoupdating America/Toronto)
```

That last one matters because it is the classic shape of this repository's documented hazard.
I checked directly: `TimeZone.autoupdatingCurrent == TimeZone.current` is **false** on this host, and `Calendar(identifier: .gregorian).timeZone == TimeZone.autoupdatingCurrent` is **false**.
The assertion is therefore not already true for an unrelated reason, and the guard dies with the line it guards.

### The timezone-preservation claim holds, measured

The commit's load-bearing behavioral claim is that attaching a calendar does not pin the fire instant.
Probe against real `UserNotifications` on the host:

```
                              TZ unset (Toronto)        TZ=Asia/Tokyo
bare (nil calendar)           2027-03-15 13:00:00Z      2027-03-15 00:00:00Z
gregorian + autoupdating tz   2027-03-15 13:00:00Z      2027-03-15 00:00:00Z
gregorian + pinned Tokyo      2027-03-15 00:00:00Z      2027-03-15 00:00:00Z
after NSKeyedArchiver trip    2027-03-15 13:00:00Z      2027-03-15 00:00:00Z

TZ=Asia/Tokyo + buddhist:  bare → nil,  autoupdating → 2027-03-15 00:00:00Z
```

The post-fix trigger is instant-identical to the pre-fix one in both zones, survives secure-coding archival with the autoupdating zone intact, and the rejected snapshot alternative demonstrably does not track.
`reviews/REVIEW-2.md:105` named exactly this trap, and the stage avoided it.

---

## Findings

### 1. P2 — two of the five changed sites have no guard on any host, and one of them is the write path into billing data

**severity:** P2, not P1: the code at HEAD is correct.
What is missing is any artifact that would notice if it stopped being correct - which is the failure `reviews/REVIEW-2.md:136-138` rejected round 1 for.

**evidence.**
In a scratch clone at `a82d4e0`, reverting **only** `CalendarDayBinding.swift` and `InsightsView.swift` to `7a3cf54`:

```
=== ONLY CalendarDayBinding+InsightsView reverted, GREGORIAN ===
✔ Test run with 178 tests in 31 suites passed after 0.050 seconds.
=== ONLY CalendarDayBinding+InsightsView reverted, BUDDHIST ===
✘ Test run with 178 tests in 31 suites failed … with 1 issue.   (DisplayFormattingTests.swift:49, pre-existing)
```

Both sites can be silently reverted and every test stays green on every environment this stage established, including the Buddhist one the whole stage exists for.
The same is true of `DisplayFormatting.swift:63`, `spokenText`'s default.
`CalendarDayBinding.asDate` is not a display seam: its `set` branch (`CalendarDayBinding.swift:20-23`) is the path by which `DatePicker` writes the user's next-charge date, trial start date and pause-resume date back into the domain (`AddEditSubscriptionView.swift:162,172,219`, `PauseFlowView.swift:40`).
On a non-Gregorian device a regression there writes era-numbered years straight into billing arithmetic, which is F1's most consequential half, and nothing would fail.
A host-side guard was available: `Tests/OttoUITests/TodaySectionPlanTests.swift` already `@testable import OttoUI` and runs under `swift test` on the host, so `asDate` is reachable without UIKit.

**why the builder missed it.**
The guard was designed around the finding's narrative ("reading sites plus the writing site") rather than around the diff.
`CalendarEraTests` covers the three sites that were easy to reach from `OttoStores`, and the two that live in `OttoUI` were fixed and then not revisited when the guard file was written in a different test target.
`.swiftlint.yml` is off limits by the ledger's own ASSUMPTION 2, which is a defensible reading, but the consequence - two sites with no enforcement of any kind - is stated nowhere.

### 2. P2 — the stage's "predicted observable difference" is false for a non-Gregorian device that already holds data, and the interaction with R0-7 is undisclosed

**evidence.**
Commit message: *"On a non-Gregorian device the stored day becomes the Gregorian one … and the trigger fires at the right moment instead of never."*
That describes a fresh install.
For a device that already has data, `PROD-READINESS.md:178` records the other half: *"F1's fix stops new corruption; every calendar day already written under a non-Gregorian device calendar stays wrong … it is the other half of F1"* (R0-7, routed to NEXT ROUND).
Those stored days are era-numbered - `reviews/REVIEW-2.md:87` measured the pre-fix Buddhist device emitting `2569`, and my own revert run reproduces `DateProvider.live` reading the Buddhist year.
After this stage, a stored `2569-08-15` is handed to a trigger that now **names** Gregorian, so `nextTriggerDate()` is a date 543 years out and the reminder never fires - where before this stage it fired correctly, because the two errors cancelled.
That is precisely the "delivers → never delivers" inversion `reviews/REVIEW-2.md:6` rejected round 1 for, relocated from new data to existing data.

**mitigation, stated fairly.** `PROD-READINESS-2.md:52` (ASSUMPTION 1) holds both real users' devices to be Gregorian, and R0-7 is on round 1's NEXT ROUND list, which round 2 is explicitly forbidden to touch.
So this is not work the stage should have done.
It is a consequence the stage should have written down, because a reader of the commit message alone concludes the opposite.

**why the builder missed it.**
The analysis was conducted entirely in the code: five conversion sites, both ends, matched.
The stored numbers those sites produced under the previous version were never brought into the frame, so "both ends move here or neither does" was applied to the code and not to the data the code has already written.

### 3. P2 — shipped source and the baseline artifact both cite `reviews-2/REVIEW-1.md`, a file that did not exist and whose contents the builder could not know

**evidence.**
`Packages/OttoUI/Sources/OttoServices/LiveNotificationClient.swift:234`: *"Measured both ways; see reviews-2/REVIEW-1.md."*
`reviews-2/BASELINE-2.md:64`: *"The consequence for this run is recorded in `reviews-2/REVIEW-1.md` and in `PROD-READINESS-2.md`'s F1 entry."*
At `a82d4e0`, `reviews-2/` contains `BASELINE-2.md` and nothing else, and `PROD-READINESS-2.md` has no F1 entry (finding 6).
Both pointers were dangling at commit time, and the target is the adversarial reviewer's own output - a document the builder does not write and cannot control.
It happens that I did measure it both ways and it does reproduce, so the citation is now accidentally true; that is luck, not evidence.
The correct target for a source comment is the stage's own record.

**why the builder missed it.**
The commit was written as if the run's documents were a single artifact being assembled in order, so a forward reference to the next file in the sequence felt like a cross-reference rather than a claim.

### 4. P2 — three verification claims are stated as passing where the commands they name exit non-zero

**evidence.**
Commit message: *"Post-fix all 16 guards pass on Gregorian, th_TH@calendar=buddhist and ar_SA@calendar=islamic-umalqura hosts, and on the simulator under `-testLanguage th -testRegion TH`."*
The guards do all pass in all four environments - I confirmed each one individually.
The runs do not:

- host, `th_TH@calendar=buddhist`: `Test run with 178 tests in 31 suites failed … with 1 issue`, exit 1.
- host, `ar_SA@calendar=islamic-umalqura`: `… failed … with 5 issues`, exit 1 (`DisplayFormattingTests.swift:49,59,68,69`, `NotificationReconciliationTests.swift:170`).
- Simulator, `-testLanguage th -testRegion TH`: `** TEST FAILED **`, exit **65**.

All of these failures are **pre-existing**: I built `7a3cf54` and reproduced the identical single Buddhist failure there (`Test run with 174 tests … failed … with 1 issue`, same file and line), so the stage regresses nothing.
Separately, the commit's fourth falsification bullet says the five-source revert on a Buddhist host produces *"5 issues"*; the command prints `with 6 issues`, the sixth being that same pre-existing failure.
The net effect is a record in which the newly established verification environments look green and are not, and in which a future reader running the command `CalendarEraTests.swift:15-20` documents gets a red run and no way to tell whether it is the guard or the noise.

**why the builder missed it.**
The runs were read for the guards rather than for the exit code, and a pre-existing failure in an environment that had never been part of any baseline had no obvious place to be recorded.
`reviews-2/BASELINE-2.md` establishes the Buddhist host as an environment but never states its baseline - which is 1 issue, not 0.

### 5. P3 — "all 16 guards" is not reproducible from the diff

**evidence.**
`git diff 7a3cf54..a82d4e0 -- '*Tests*.swift' | grep -cE '#expect|#require'` on added lines = **14**, across **6** `@Test` functions in 3 suites.
No count in the diff comes to 16.
The plausible reading (14 new assertions plus the 2 pre-existing `LiveNotificationClientTests` assertions the commit says it re-checked) is not stated.

**why the builder missed it.**
A number carried from a working note and never re-derived from the committed diff.

### 6. P3 — the ledger records nothing about this stage

**evidence.**
`PROD-READINESS-2.md:30` still reads `| 1 | **F1** | The calendar defect, both ends together | *(pending)* |`, and `:38` says terminal states are RESOLVED, DEFERRED or REJECTED TWICE and *"There are no others."*
`:46` still carries the literal placeholder `7a3cf54..<stage-0 head>` in the REVIEW RANGES table, and there is no row for this stage at all - the table that `:42` introduces as the fix for round 1's RF-2 blind spot.
`a82d4e0` touches no document: the entire account of this stage is the commit message.

**why the builder missed it.**
The ledger row is presumably being held for the review verdict.
Round 1's RF-2 is the demonstration that "I will record it later" is how commits fall outside every range, so the range and the reviewed head - both of which were knowable at commit time - should have gone in with the commit.

### 7. P3 — "against real iOS UserNotifications" overstates what the Simulator run exercises

**evidence.**
`LiveNotificationClientTests.swift:18-80` injects `FakeUserNotificationCenter`; `LiveNotificationClient.swift:58-60` only reaches `UNUserNotificationCenter.current()` when no center is passed.
On the Simulator the *framework types* are real - `UNCalendarNotificationTrigger`, its component normalization, and `nextTriggerDate()` - and that is exactly the code F1 turns on, so the evidence is real and valuable.
The center, the daemon, and the archive/restore round trip through it are not exercised anywhere, which `PROD-READINESS-2.md:59` correctly lists under CANNOT ASSESS.
The commit message's phrasing invites a stronger reading than the ledger's.

**why the builder missed it.**
"Real iOS `UserNotifications`" is true of the class under test and false of the subsystem; the commit message used the subsystem's name.

---

## Checked and found clean

- **SwiftData schema.** No schema change of any kind. The diff touches no `@Model`, no `VersionedSchema`, no `SchemaMigrationPlan`, no migration stage, and no file under `Packages/OttoPersistence`. `git diff 7a3cf54..a82d4e0 | grep -E '^\+.*(@Model|VersionedSchema|SchemaMigrationPlan|@Attribute|@Relationship|SchemaV)'` returns nothing. V3 is untouched.
- **Prohibited actions by the builder.** Files changed in the range are 11: the two round-2 documents and 9 source/test files. `.swiftlint.yml`, `.github/workflows/`, `Package.swift`, `project.yml`, `PROD-READINESS.md` and everything in `reviews/` are untouched. No new dependency, no new config key. Reflog shows two ordinary commits on `prod-readiness-2/2026-08-10` and no rebase, reset, amend or tag operation. `.git/FETCH_HEAD` does not exist and `refs/remotes/origin/main` still points at `406a5a6`, so no fetch or pull landed.
- **No features smuggled.** `CalendarDay.conversionCalendar` is new public API, but it is a seam required by the fix and forced into `OttoDomain` by the module graph (`Packages/OttoUI/Package.swift:30-52` - all three targets depend on `OttoDomain`, which is precisely `reviews/REVIEW-2.md:154`'s point). No new user-visible capability, no new screen, no new stored field.
- **Severity is neither inflated nor deflated.** The stage claims no severity of its own; F1 keeps round 1's P1. The commit does not claim F1 is closed beyond the code, and does not claim the device question is settled.
- **The fix does not relocate the bug within the code.** Only one `UNCalendarNotificationTrigger` construction exists in the tree (`LiveNotificationClient.swift:242`), so the writing side is complete. Every remaining `Calendar.current` in production code is at `SettingsView.swift:85,93`, which handles hour and minute only; I measured that hour/minute components are identical between `Calendar.current` and Gregorian on a Buddhist host, so that site is correctly out of scope. `NotificationContent.swift:152` and `SubscriptionReadRepair.swift:175` already pin Gregorian explicitly.
- **Error handling.** No error path changed. `DateProvider.swift:40-44`'s `preconditionFailure` and the `displayText` / `asDate` fallbacks are all context lines, unmodified. Nothing new is swallowed.
- **Verification exercises the changed path.** `pendingRoundTrip` (`LiveNotificationClientTests.swift:177-182`) and `addTranslatesCalendarTrigger` (`:104-124`) both run `add` with the attached calendar and both pass, so the readback claim - fields unchanged, `components.timeZone` still `nil` - is exercised rather than asserted.
- **No guard that stays green before and after.** Every new assertion was individually falsified above: the trigger guard fails on a Gregorian host when the fix is removed, the three era guards fail on a Buddhist host when their sites are reverted, and the timezone guard fails when its line is deleted. `CalendarEraTests.swift:12-13,22-23` states in the file itself that it guards nothing on a Gregorian host, and `:15-20` records the command that makes it fail; that self-description is accurate, and I confirmed the file is inert on Gregorian.
- **No assertion true for an unrelated reason.** Checked the two candidates: `TimeZone.autoupdatingCurrent == TimeZone.current` is false here, and `Calendar.dateComponents(_:from:)` does not attach a calendar to its result, so `CalendarEraTests.swift:45`'s `DateComponents` equality is a real comparison.
- **"Cannot be verified" claims.** The one this stage overturns (round 1's F1 unverifiability) is genuinely overturnable, and I reproduced the overturning independently on both the host and the Simulator. The claims this stage still makes - device round trip, Release behavior, real delivery - are correctly scoped to hardware and are not asserted as verified.
- **Citations that were checked and are accurate.** `reviews/REVIEW-2.md` finding 4 (`:147-155`) does say the round-1 constant sat in `OttoStores` and that `OttoServices` cannot reach it. `reviews/REVIEW-2.md:140-142` does recommend a `custom_rules` entry as this repo's idiom, as `PROD-READINESS-2.md:53` claims. `PROD-READINESS.md:133` does contain the "unverifiable on this host by construction" wording quoted in `reviews-2/BASELINE-2.md:45`. `PROD-READINESS.md:119,204` do record the round-1 attempt, rejection and revert at `b582d94`.
- **Round-1 review findings this stage silently closes.** `reviews/REVIEW-2.md` finding 5 (the process-lifetime timezone snapshot in `InsightsView.monthText`) is closed by making `conversionCalendar` a computed property with an autoupdating zone, and finding 6 (`DateProvider`'s doc comment made false) is closed by rewriting `DateProvider.swift:30-34`. Neither is claimed in the commit message; both hold.
- **Foundation's `.gregorian` is proleptic here.** Checked, because `CalendarDay`'s arithmetic is proleptic and a Julian cutover would make the doc comment wrong: `Calendar(identifier: .gregorian)` and `Calendar(identifier: .iso8601)` resolve `1500-01-01` to the same instant on this host, so no cutover applies and `conversionCalendar` does match `ordinalDay`'s rules.

## Prohibited actions by me: none, and what I did instead

- No network call of any kind. No `git ls-remote`, `git fetch` or `git pull`. Remote state was read with `git show-ref` and `git remote -v` only; `git clone /Users/<user>/dev/otto <scratch>` is a local-filesystem clone.
- No device. Two Simulator runs only (`id=<simulator-udid>`), one default and one `-testLanguage th -testRegion TH`.
- No edit to any repository file except this one. All falsification edits were made in throwaway clones under the session scratch directory, outside the repository, and those clones were reset to `a82d4e0` after each run.
- Nothing deleted, nothing in `<backup-dir>` touched, no `rm -rf`.
- `scripts/verify.sh` writes only to its own `mktemp` directory on success, and it exited 0, so no `verify-*-failure.log` was produced.

Repository state at the end of this review: `git rev-parse HEAD` = `a82d4e0b345b8f47b54ad897a99ebfae503b5922`, `git status --porcelain` empty apart from this file.
