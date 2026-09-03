# REVIEW-3 — stage 3, range e4f4872..b006d20

verdict: PASS-WITH-FINDINGS

The stage does the thing it set out to do.
`device_calendar_outside_conversion_seam` is a real guard: it fires at every one of the six sites the ledger's falsification table names, in all three packages' `Sources/` and in the app target, at `severity: error`, and CI runs `swiftlint --strict` (`.github/workflows/ci.yml:80`), so a reverted F1 site now reddens a Gregorian machine.
Its comment immunity is not decorative - I removed `match_kinds` and got 8 violations across five files' prose, which is the exact hole it closes.
No existing lint rule was relaxed, no `excluded:` path was added, no schema file was touched, and the baseline did not regress on any of the four measurements.

Nine findings, none of which invalidates the stage.
Two are load-bearing against claims the ledger makes rather than against the guard's existence.

The first is the shape the prompt asked me to hunt: the rule is spelled against `Calendar.current`, and the codebase's own house idiom for that value is `.current`, which the regex cannot see.
Four of the six sites in the ledger's own table can be reverted with `swiftlint --strict` exit 0 by changing `= CalendarDay.conversionCalendar` to `= .current` - a change that sits two tokens away from `timeZone: TimeZone = .current` on the same signature.
The ledger's "What this does NOT do" discloses the implicit-formatter blind spot and not this one.

The second is that `reviews-3/REVIEW-2.md` finding 6 is recorded "Now guarded" and only half of it is.
The new test is titled "deduplicated and in day order"; deleting `.sorted()` from the shipped source leaves all 258 OttoDomain tests green, because the fixture's candidate order is already sorted.

## What I ran

All mutation work in three detached worktrees under a scratch path I created, at `b006d20`, `49ba021` and `e4f4872`.
The main tree was never modified, no commit was created, and all three worktrees are removed (`git worktree list` shows only the repository).
The main tree carries the builder's concurrent stage-4 edits, which are outside this range and which I did not touch; every citation below is against the file content at `b006d20`, read from my worktree, not from the live tree.

**Baseline, all four measurements, at the reviewed HEAD.**

```
$ ./scripts/verify.sh                    # exit 0
== VERIFIED: b006d209442e8bb2881c046e94ef63e81e51966c builds, tests, and lints from a clean clone
   OttoDomain: 258
   OttoPersistence: 119
   OttoUI: 203
   total: 580 tests

$ swiftlint --strict                     # SwiftLint 0.65.0
Done linting! Found 0 violations, 0 serious in 215 files.

$ cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"   # exit 0
✔ Test run with 113 tests in 21 suites passed after 3.170 seconds.
✔ Test run with 72 tests in 12 suites passed after 0.061 seconds.
✘ Test run with 31 tests in 6 suites passed after 2.976 seconds with 7 known issues.
** TEST SUCCEEDED **

non-Gregorian harness (command from CalendarEraTests.swift's header, bundle path absolute, run from the repo root):
  th_TH@calendar=buddhist          203 tests, 1 issue   DisplayFormattingTests.swift:49
  ja_JP@calendar=japanese          203 tests, 1 issue   DisplayFormattingTests.swift:49
  ar_SA@calendar=islamic-umalqura  203 tests, 5 issues  DisplayFormattingTests.swift:49,59,68,69
                                                        NotificationReconciliationTests.swift:170
```

565 → 580 is exactly the fifteen tests this run has added (1 + 10 + 2 + 2) and nothing else.
The simulator's buckets are 113 / 72 / 31 against the baseline's 108 / 70 / 31: the second bucket moved because `SettingsStoreTests` lives in `OttoStoresTests`.
The 7 known issues are the same seven `EmptyStateTests` accessibility-label assertions, and the non-Gregorian issue counts and citations are the five `BASELINE-3.md:143-171` records.
Nothing failed that passed before.

**Every commit in the range builds, all three packages.**

```
49ba021  OttoDomain Build complete! (11.90s)  OttoPersistence (14.31s)  OttoUI (16.71s)  swiftlint --strict exit 0
3c0577b  PROD-READINESS-3.md only (git diff --stat 49ba021 3c0577b: 1 file changed, 2 insertions, 1 deletion) - identical code tree
b006d20  verify.sh above, which clones the committed HEAD and also builds the app target
```

**Lint-rule falsification, one site at a time, in the `b006d20` worktree.**
Every row of `PROD-READINESS-3.md:330-337` reproduces exactly.

```
DateProvider.swift:38:30                1 violation
DisplayFormatting.swift:39,46,63        3 violations
CalendarDayBinding.swift:11:38          1 violation
InsightsView.swift:147:26               1 violation
LiveNotificationClient.swift:236:35     1 violation
SettingsStore.swift:105:9 / :114:21     1 each, 2 together
```

**Scope probes.** The rule fires in `Otto/App/OttoApp.swift` (app target) and in `Packages/OttoPersistence/Sources/OttoRepositories/` (a third package), and on `Calendar.autoupdatingCurrent` as well as `Calendar.current`, and on a `Calendar\n    .current` split across lines.
It does not fire on a string literal containing the text, on a `//` comment, or on a doc comment - and it does not cover `Packages/*/Tests`, which dodges nothing, since every occurrence in a test file at `b006d20` is prose.

**`match_kinds` is load-bearing, proved by removing it:** 8 violations appear, in `CalendarDay.swift:160,165`, `StoredDayPlausibility.swift:7`, `DisplayFormatting.swift:34`, `LiveNotificationClient.swift:228` and `SettingsStore.swift:92,94,98`.

**The stage's opening reconfirm reproduces**, at `e4f4872` with `DateProvider` and `CalendarDayBinding` reverted:

```
✔ Test run with 201 tests in 37 suites passed after 10.373 seconds.
$ swiftlint --strict --quiet    # exit 0, no output
```

**Mutation testing of every test added or changed in the range**, listed under Explicit checks 10 below.

**Two independent re-derivations against Foundation**, both from a standalone `xcrun swift` script that does not import the package: the sixteen-identifier offset table, and the ledger's 4001-anchor specificity scan of the rejected `createdAt` rule.

## Findings

### 1. The rule cannot see `.current`, which is the spelling the guarded signatures already use for their other two device values

- severity: **P2**
- evidence: the regex is `'\bCalendar\s*\.\s*(?:current|autoupdatingCurrent)\b'` (`.swiftlint.yml:59`).
  It requires the type name to be written.
  Four of the six sites in the ledger's own falsification table are default parameters of type `Calendar`, where Swift's implicit member syntax makes the type name unnecessary - and the codebase already writes exactly that form for the neighbouring parameters.
  `DisplayFormatting.swift:63-65` is three lines of it:

  ```swift
  calendar: Calendar = CalendarDay.conversionCalendar,
  timeZone: TimeZone = .current,
  locale: Locale = .current
  ```

  Changing that first line to `calendar: Calendar = .current`, at all three `DisplayFormatting` defaults and at `CalendarDayBinding.swift:11`, in the `b006d20` worktree:

  ```
  === BLIND: implicit member .current in DisplayFormatting defaults (x3): rc=0 seam_violations=0
  === BLIND: implicit member .current in CalendarDayBinding:              rc=0 seam_violations=0
  ```

  `swiftlint --strict` exits 0.
  `CalendarDayBinding.asDate` is the DatePicker **write** path, so this is the F1 defect - era-numbered years written into billing data - restored at the site the stage exists to protect, with the new gate silent on the machine CI runs.
  Two further spellings are equally invisible: `Locale.current.calendar` (`rc=0`, and it is the device calendar by definition) and `Calendar(identifier: Locale.current.calendar.identifier)` (`rc=0`).
  Deleting `components.calendar = CalendarDay.conversionCalendar` outright at `LiveNotificationClient.swift:236` also lints clean, and that reinstates the nil-calendar defect the comment three lines above it describes.
  `PROD-READINESS-3.md:348-352` discloses only the implicit-`Date.FormatStyle` blind spot and the "cannot check `conversionCalendar` is still Gregorian" one; the implicit-member spelling is not named there or anywhere in the section.
- why the builder missed it: the falsification protocol was "revert the site to `Calendar.current` and count violations", so every experiment wrote the string the rule was written from.
  A regex tested only against its own generating example measures nothing about the space of edits a future author will actually make, and the edit most available to that author here is the one that makes the line look like the two beneath it.

### 2. REVIEW-2's finding 6 is recorded closed, and the ordering half of the contract is still unguarded

- severity: **P2**
- evidence: `PROD-READINESS-3.md:232` says the `deduplicated and in day order` contract is "Now guarded", citing the dedup falsification.
  The new test is `StoredDayPlausibilityTests.swift:189`, titled "⛔ the reported days are deduplicated and in day order", and it asserts sortedness at `:205` with `#expect(reported == reported.sorted())`.
  Deleting `.sorted()` from `StoredDayPlausibility.swift:104`, whole OttoDomain suite:

  ```
  === DROP .sorted() from implausibleStoredDays: rc=0
      ✔ Test run with 258 tests in 57 suites passed after 0.061 seconds.
  ```

  The dedup half does bite (`rc=1`, 2 issues at `:204` and `:206`), so half the finding is genuinely closed.
  The ordering half cannot bite because the fixture's candidate order is `[08-06, 08-06, 08-20, 08-06]`, which dedups to `[08-06, 08-20]` - already sorted, so `.sorted()` is a no-op on it.
  A one-line change to the same fixture would catch it.
  I added a probe using `lastUsedDate` **earlier** than the anchor, which is an entirely ordinary shape, and it fails the moment `.sorted()` goes:

  ```
  == probe added, source intact                rc=0   8 tests passed
  == probe added, .sorted() REMOVED            rc=1
     ✘ PROBE: ordering with an unsorted candidate order ... Expectation failed:
       subscription.implausibleStoredDays(asOf: today) == [try day(2569, 8, 1), try day(2569, 8, 6)]
  ```
- why the builder missed it: the falsification that was run is the one the reviewer described (remove the `Set`), and its output - a four-element list with duplicates - fails the equality assertion so loudly that the second half of the contract never gets its own experiment.
  A test whose title names two properties needs a fixture that separates them; this one holds both properties in a single `==` against a literal, where the dedup violation masks the ordering one.

### 3. The measurement that decides against the `createdAt` alternative is a property of the reviewer's arbitrary K, not of the design, and was not varied

- severity: **P2**
- evidence: `PROD-READINESS-3.md:221-226` rejects REVIEW-2's proposed `createdAt` cross-check on a measured specificity cost: "scanned 4001 ordinary anchors; 64 would be FLAGGED as corrupt", reported as "**1.6% false positives on ordinary data**, in a ~64-day band".
  `REVIEW-2.md` states its K plainly - "I tested this on the anchor only, with **K = 31 days**" - and disclaims a finished design.
  Re-derived independently (standalone script, `America/Toronto`, `createdAt` = Gregorian 2026-08-06, thirteen non-Gregorian identifiers, flag if any calendar reads the stored triple to within K of `createdAt`), scanning the same 4001 daily anchors:

  ```
  K=31: FLAGGED=63 (1.57%)   e.g. 2018-12-31, 2018-12-30 ... by ethiopicAmeteMihret
  K=7:  FLAGGED=14 (0.35%)
  K=1:  FLAGGED=2  (0.05%)   2018-11-30 and 2018-12-01, by ethiopicAmeteMihret
  ```

  And the sensitivity the ledger concedes is right does not depend on K at all, because a corrupt triple resolves to `createdAt`'s own day:

  ```
  K=31: createdAt rule sensitivity 13/13
  K=1:  createdAt rule sensitivity 13/13
  ```

  So the number carrying the decision is **30x** larger than the same rule at a one-day window with identical sensitivity.
  The irreducible part of the ledger's argument survives - Ethiopic 2018-11-30 *is* Gregorian 2026-08-06, so an exact-match rule still flags that one anchor, and a false positive here does silence reminders on a working subscription.
  That is a real objection at 0.05%; it is a different objection from the one the ledger makes at 1.6%.
  Separately, my count is 63 where the ledger says 64, which is a boundary difference rather than a disagreement, but it means the ledger's figure is not reproducible to the digit.
- why the builder missed it: the reviewer supplied a rule *and* a constant, and the rebuttal treated them as one artifact.
  Measuring the proposal as given is the right instinct; the step not taken is the one this run applies everywhere else - vary the parameter and see whether the conclusion is about the design or about the number.

### 4. Stage 3 records none of the four baseline measurements, which is the finding stage 2 just accepted

- severity: **P3**
- evidence: `BASELINE-3.md:17` fixes the standard, and `PROD-READINESS-3.md:228` accepts REVIEW-2 finding 2 and points at the new table at `:240-247` as the remedy.
  ITEM 3 (`:298-353`) contains no `verify.sh` total, no simulator run, no non-Gregorian run, and no `swiftlint --strict` result at the stage's end; its only counts are `201 tests` (`:307`) and the per-site violation table, both from the *pre-rule* state.
  The one table that does exist is now stale at HEAD: `:244` says 258 / 119 / 201 = **578**, measured 580; `:246` says simulator **113** / 70 / 31, measured 113 / **72** / 31.
  Both are accurate for `49ba021`, which is where they were written, and neither is accurate for the commit the range closes at.
- why the builder missed it: the remedy for finding 2 was implemented as a table inside ITEM 1 rather than as a step at the end of a stage, so it records a moment rather than a HEAD, and stage 3's own two tests landed after it.
  I have measured all four here, so the record exists either way.

### 5. "Reconfirmed at HEAD" under ITEM 3 was measured at the range's parent, and at HEAD it produces the opposite result

- severity: **P3**
- evidence: `PROD-READINESS-3.md:303-310` is headed "**Reconfirmed at HEAD by executing the defect**" and reports `201 tests` and `LINT CLEAN (nothing noticed)` after reverting two F1 sites.
  At `b006d20` that experiment yields 203 tests and two lint errors, because the rule this stage adds is what makes it fail.
  The experiment is correct and necessary - you cannot demonstrate the gap with the gate installed - and it reproduces exactly at `e4f4872` (201 tests passed, `swiftlint --strict` exit 0, transcript above).
  The defect is the label: in a ledger where "at HEAD" is a term of art for the committed state, this one block means "at the state before this stage".
- why the builder missed it: the section was written while `e4f4872` *was* HEAD, and the heading is boilerplate reused from ITEM 1 and ITEM 2, where it is accurate.

### 6. A shipped doc comment states a Foundation behaviour that measurement contradicts

- severity: **P3**
- evidence: `SettingsStore.swift:94-96` justifies the change with "`Calendar.current` reads `DateComponents(year: 2000, …)` as year 2000 OF THE DEVICE'S ERA, which on a Buddhist device is 1457 CE and **in a Japanese era is a year that does not exist**."
  Asked of Foundation instead (standalone script, `America/Toronto`, `year: 2000, month: 1, day: 1, hour: 9`):

  ```
  gregorian         2000-01-01 09:00   roundtrip h=9 m=0
  buddhist          1457-01-01 09:00   roundtrip h=9 m=0
  japanese          4018-01-01 09:00   roundtrip h=9 m=0
  hebrew            1762-09-17 09:00   roundtrip h=9 m=0
  islamic-umalqura  2562-01-08 09:00   roundtrip h=9 m=0
  indian / chinese / persian / roc      all resolve, all roundtrip h=9 m=0
  ```

  The Buddhist half is exact.
  The Japanese half is not: the components resolve to a real instant in 4018, not to nothing, so the `?? Date(timeIntervalSinceReferenceDate: 0)` fallback the sentence implies is never reached.
  The measurement also strengthens the stage's own **behaviour-preserving** claim at `:322` rather than weakening it: hour and minute round-trip identically in all nine calendars, so on a non-Gregorian device the picker showed and still shows the stored time, and this refactor changes the instant behind the wheel and nothing a user can see.
- why the builder missed it: the sentence is doing rhetorical work - a second, worse example after the Buddhist one - and it is the only claim in the section that was not put to Foundation, in a stage whose central test exists precisely because a list of era offsets was recited instead of measured.

### 7. The coverage test's floor has one unit of slack, so the hand-maintained list can silently lose an entry

- severity: **P3**
- evidence: `StoredDayPlausibilityTests.swift:27` is the one hand-maintained list in the file, and its comment says a future SDK's new calendar "must be added here".
  The degeneracy guard at `:101` is `#expect(caught >= 10, ...)`; the measured value is 11 (16 identifiers, minus the three that write the Gregorian numbers, minus the two known-uncatchable).
  Deleting `("buddhist", .buddhist)` from the list:

  ```
  === drop buddhist from allIdentifiers: rc=0
      ✔ Test run with 7 tests in 1 suite passed after 0.001 seconds.
  ```

  The same slack absorbs a calendar silently skipped by the `guard let stored = CalendarDay(...) else { continue }` at `:88` - which is reachable in principle, since Ethiopic and Hebrew both have a 13th month that `CalendarDay.init?` rejects, and only the choice of instant keeps it from firing here.
  Everything else about the test is strong: threshold 100 → 3000 fails it with `caught → 1`, threshold 100 → 5 fails it with `missed → []`, and it passes under all three non-Gregorian locales.
- why the builder missed it: `>= 10` is a canary against "the loop reached nothing", and against that failure mode it works.
  It doubles as the only thing standing between the list and a silent deletion, and for that job it needs to be `== 11`, or the count needs to come from the list rather than from a literal.

### 8. Nothing asserts that the screen uses the API the stage moved to the store

- severity: **P3**
- evidence: `SettingsStore.swift:100-102` gives the reason for the move - the view's binding "is inside a `private struct` no test can reach, and F1's whole lesson is that an unreachable conversion is an unguarded one" - and the two new tests exercise `notificationTimeOfDay` and `setNotificationTime(from:)` directly.
  `ReminderDefaultsSection` is still `private struct` (`SettingsView.swift:35`), no test in `Packages/OttoUI/Tests` references `SettingsView` or its binding, and the simulator suite's 31 UIKit-hosted tests are `EmptyStateTests` and friends.
  So the conversion is now reachable, and the *wiring* from the DatePicker to it is not: replacing `get: { settings.notificationTimeOfDay }` with any other expression is lint-clean and test-green.
  The lint rule does cover a `Calendar.current` reintroduction in the view, which is the specific regression the stage was aiming at, so this is a residual rather than a gap in the stage's own claim.
- why the builder missed it: the stated goal was reachability of the conversion, and that goal is met; the binding was treated as a two-line adapter rather than as the only path a user's input actually takes.

### 9. The rule's inline comment names three of the five files it is protecting

- severity: **P3**
- evidence: `.swiftlint.yml:62-66` justifies `match_kinds` with "The doc comments at CalendarDay.swift, DisplayFormatting.swift and LiveNotificationClient.swift name `Calendar.current` deliberately".
  Removing `match_kinds` produces violations in five files, not three - `StoredDayPlausibility.swift:7` and `SettingsStore.swift:92,94,98` are also protected by it, and `SettingsStore.swift` is this stage's own new file content.
  The ledger body at `:325-328` has all five right; only the comment a future author reads at the rule is short by two.
- why the builder missed it: the YAML comment was written before the ledger paragraph, and `SettingsStore.swift` acquired its three occurrences later in the same stage.

## Explicit checks

1. **Fabricated or unreproducible findings.** Every measured number in ITEM 3 reproduces: the six-row violation table exactly, the "201 tests + LINT CLEAN" reconfirm exactly at `e4f4872`, the "~0.015 s / no suite time change" cost (203 tests in 12.4 s under the harness against REVIEW-2's 201 in 12.9 s). In ITEM 1's remediation, the sixteen-identifier offset table reproduces digit for digit against Foundation, including the surprising `ethiopicAmeteAlem` row (it really does write 2026-8-6). The 4001-anchor scan reproduces in substance at 63 rather than 64 (finding 3).
2. **Citations that don't say what they're claimed to say.** Two, both P3: "Reconfirmed at HEAD" (finding 5) and the three-of-five file list (finding 9). `REVIEW-2.md` finding 6 and finding 1 are characterised accurately in the remediation list, except that finding 6 is described as closed when half of it is (finding 2). `DisplayFormattingTests.swift:49` is cited as the implicit-`Date.FormatStyle` failure and it is exactly that, under all three locales.
3. **Severity inflation or deflation.** One case, finding 3: 1.6% is reported as a property of a rejected design and is a property of one parameter value. Nothing is deflated. The ITEM 1 terminal state now reads "RESOLVED as detection for 11 of 13 / DEFERRED as repair", which is the honest label for what I measured (11 caught, 2 uncatchable, 3 calendars that cannot corrupt anything).
4. **Features smuggled past the no-features rule.** None. The only production change is the `SettingsStore` extraction, and it is behaviour-preserving on every calendar Foundation offers: hour and minute round-trip identically in all nine I tested, and `DatePicker(displayedComponents: .hourAndMinute)` renders only those two. `SettingsView.swift`'s diff is confined to the binding. `NotificationScheduler.swift`'s eight added lines are all `//`. `StoredDayPlausibility.swift`'s change is doc comment only - `plausibleStoredDayYears = 100` and `implausibleStoredDays` are byte-identical to `e4f4872`. No new screen, setting or navigation.
5. **Any SwiftData schema change.** None. `git diff --name-only e4f4872..b006d20` touches nine files, none under `Packages/OttoPersistence/Sources`, no `OttoSchemaV*.swift`, no `OttoMigrationPlan.swift`, no `Package.swift`.
6. **Prohibited actions.** None found. No `.github/workflows/` change, no narrative document change, no new dependency, no config key beyond the permitted `custom_rules` entry. `.swiftlint.yml`'s diff is 32 added lines and 0 removed: no rule relaxed, disabled or re-thresholded, no `excluded:` added, and the new rule has no `excluded:` at all. Its `included:` scoping dodges nothing - at `b006d20` there is no `Calendar.current` in any Swift **code** anywhere in the repository, only in prose. `git reflog --all` shows the three range commits as plain `commit:` entries; every `reset`/`amend` in the reflog is from 2026-08-07/08, before this run opened. `refs/remotes/origin/main` is still `406a5a6`, matching `BASELINE-3.md`, and there is no `FETCH_HEAD`. No tags exist. I ran no network command.
7. **Fixes that relocated a bug rather than removed it.** The `SettingsView` → `SettingsStore` move is genuinely behaviour-preserving, proved rather than argued (check 4 above, plus the round-trip test failing under both of my two implementation mutations). Both silent fallbacks moved verbatim - `?? Date(timeIntervalSinceReferenceDate: 0)` and `?? FireTimePolicy.standard.preferredHour` - and neither is reachable with a Gregorian calendar and valid components. Under the non-Gregorian harness the relocated code passes, and a lint-blind revert of it (`Locale.current.calendar`) is caught there: `SettingsStoreTests.swift:81 (store.notificationTimeOfDay → 1457-01-01 …) == (expected → 2000-01-01 …)`.
8. **Error handling that hides errors.** Nothing new. The two `??` fallbacks are pre-existing and relocated; no `try?`, no empty `catch`, no swallowed result introduced in the range.
9. **Verification that doesn't exercise the changed path.** The lint falsifications exercise each guarded site individually and the rule's message text is what appears. The gap is finding 8: the DatePicker binding itself is exercised by nothing.
10. **Tests that pass for the wrong reason.** I broke the thing each added or changed test claims to guard.

    | test | mutation | result |
    |---|---|---|
    | `coverageAcrossFoundationsCalendars` | threshold 100 → 3000 | fails, `caught → 1`, `missed` = 12 calendars |
    | | threshold 100 → 5 | fails, `missed → []` |
    | | drop `buddhist` from the list | **passes** - finding 7 |
    | `noThresholdCatchesTheTwo` | threshold 100 → 5 | fails on both 2018-11-30 and 1948-05-15 |
    | `reportedDaysAreDedupedAndSorted` | remove the dedup `Set` | fails at `:204` and `:206` |
    | | remove `.sorted()` | **passes** - finding 2 |
    | `notificationTimeRoundTrips` | read `.minute` as the hour | fails on 4 of 5 pairs |
    | | hardcode `hour: 9` in the getter | fails on 4 of 5 pairs |
    | `notificationTimeReferenceInstantIsGregorian` | revert to the device calendar, buddhist harness | fails, `1457-01-01 … == 2000-01-01 …` |
    | | same revert, Gregorian host | passes - as the ledger states, and the lint rule is the guard there |

11. **Flaky or environment-dependent tests.** None found. `SettingsStoreTests` allocates a UUID-named `UserDefaults` suite per test and removes its persistent domain (`:11-16`). The domain tests pin one instant and one timezone with an explicit `TimeZone(identifier:)`. All five new/changed tests pass on the host and under all three non-Gregorian locales. The `allIdentifiers` list is SDK-coupled by construction and says so; the run is not otherwise environment-dependent. The four `OSLogStore` tests remain the standing risk and are untouched by this range.
12. **Anything marked resolved without an artifact.** One: REVIEW-2 finding 6, half-artifacted (finding 2). Every other remediation bullet at `:210-238` has an artifact I could re-run. ITEM 3's "RESOLVED" is backed by a rule I falsified at six sites.
13. **Every commit in the range builds.** Swept: `49ba021` builds all three packages and lints clean; `3c0577b` is a two-line ledger edit over the same code tree; `b006d20` is covered by `verify.sh`, which also builds the app target.
14. **The baseline must not regress.** It does not. 565 → 580 host tests is exactly this run's fifteen added tests; `swiftlint --strict` clean; simulator `** TEST SUCCEEDED **` with the same 7 known `EmptyStateTests` issues and 31 unchanged in the bucket that carries them; non-Gregorian 1 / 1 / 5 at the same five file:line citations. I ran all four rather than reasoning about any of them.

## What I could not check, and why

- **CI itself.** I confirmed `.github/workflows/ci.yml:80` runs `swiftlint --strict`, so the new rule gates CI at `severity: error`, but no CI run may be triggered from this run and I did not read one. The claim "fails the build on the machine CI uses" is verified on a machine of that kind, not on the runner.
- **Whether iOS's calendar picker offers Ethiopic or Indian.** REVIEW-2 could not determine it from this host and neither can I; the residual's real-world reach is therefore still unquantified, which is the state the ledger carries to NEXT ROUND.
- **Release configuration and a physical device.** Debug and simulator only, as every round has been; a physical device is prohibited this run.
- **The `OSLogStore` tests on a CI runner.** Unchanged from BASELINE-3's CANNOT ASSESS. This range adds no fifth log-reading test - the two it adds are pure value tests - so it does not deepen that risk.
- **Every non-Gregorian calendar at runtime.** The harness covers Buddhist, Japanese and Islamic-umalqura. Ethiopic and Indian, the two the detector cannot catch, were exercised through Foundation and through the ledger's own scheduler probe in REVIEW-2, not through a process running under those locales.
- **The exact provenance of the ledger's `64`.** My re-derivation gives 63 under the parameters the reviewer stated; the one-anchor difference is a boundary convention I could not pin down without the builder's script, which is not in the repository.

Worktrees removed - `git worktree list` shows only `/Users/<user>/dev/otto`.
The main working tree was never modified by this review; its dirty files are the builder's concurrent stage-4 work, and the only file this review writes is `reviews-3/REVIEW-3.md`.
No commit was created.
