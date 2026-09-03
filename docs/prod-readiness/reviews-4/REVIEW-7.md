# REVIEW-7 - round 4, stage 6r (the REJECT's remediation)

Range reviewed: `92174e4..040ecd2` (5 commits).
Reviewed head: `040ecd2`.
Ledger: `PROD-READINESS-4.md`. Baseline: `reviews-4/BASELINE-4.md`.
The verdict this range answers: `reviews-4/REVIEW-6.md` (**REJECT**, four P2s and five P3s).

Every `PROD-READINESS-4.md:NNN` citation below is a line number in `git show 040ecd2:PROD-READINESS-4.md`.
I am a different reviewer from the one that wrote `REVIEW-6.md`, and I re-derived its findings rather than inheriting them.

verdict: REJECT

## Summary

The code in this range is small, correct and better-guarded than what it replaces.
All five baseline dimensions reproduce at `040ecd2` exactly as the ledger records them, every commit in the range builds all three packages, the SwiftData schema is untouched, `.swiftlint.yml`, `.github/workflows/`, every `Package.swift` and `project.yml` are untouched, nothing was pushed or rewritten, no test was weakened and no lint rule was relaxed.
The one persistence-package file in the diff is comment-only, verified line by line.

**`REVIEW-6.md` finding 2 is genuinely closed.** Deleting the `catch`-branch generation guard now fails the simulator suite with exactly **1 issue**, at `SettingsExportWithdrawalTests.swift:192`, reading `(.failed("...SnapshotRefused...")) == .notPrepared` - the ledger's recorded falsification to the digit, and the new test drives the shape that was produced by nothing before (a build that is superseded and *then* fails).
`REVIEW-6.md` finding 8 is closed: `OttoLog.swift`'s doc comment now says the composition is a convenience and not the guard, which is true, and names where the guard is, which is correct.
`REVIEW-4.md` finding 10 is closed: I read the implementation and the new protocol contract describes it accurately, including that the save commits on `mutated` rather than on `invalidated`.
The R4-3 emission guard bites twice: reverting the pass-end call site to the pre-fix interpolation gives **2 issues**, and retagging the test's own production pass gives **1 issue** at the pinned `#require`, measured against the full 209-test process rather than a filtered one.
The asymmetric plausibility window is well guarded - reverting `plausibleStoredDayYearsBehind` to round 3's 100 gives **17 issues** across three tests, and the newly added month loop is one of the assertions that fires.

It is rejected for three things, all of which are the failure mode the reject was for.

**First, `docs/next-wave.md` - the run's only user-facing deliverable, rewritten twice already for shipping a false statement - now ships a third one, and this one is refuted by the ledger's own carried finding on the facing page.**
The section this range added closes with: *"None of them can be prompted by a notification, because **a subscription with any corrupt day schedules no reminders at all**"*.
Measured through the real `NotificationScheduler`: an active subscription with an Indian/Saka-corrupt anchor is scheduled **4** notifications, a Japanese-corrupt one **4**, and a subscription with a Buddhist-corrupt `lastUsedDate` **3**.
Only a *forward*-offset corruption schedules zero, and forward is 2 of the 11 calendars the rule detects.
`PROD-READINESS-4.md:663` (`N4-2`, carried at P2 in the same file) says this in the ledger's own words: *"For every **negative**-offset calendar the planner still produces rungs from the corrupt anchor and the pass still schedules them … Japanese, Minguo, Islamic and Persian each schedule 4 reminders on the wrong days. Round 4 adds Indian to that set."*
The `lastUsedDate` row itself is materially fixed and I confirmed every measurement in it.
The sentence that was added on top of it was not verified against anything, and it tells the population round 4 just made detectable that reminders they are visibly receiving cannot be happening.

**Second, `REVIEW-6.md` finding 3 was the finding about corrections announced and not applied, and its own fix stops one row short of the table it was given.**
`REVIEW-6.md`'s finding 3 tabulated four surviving statements. Three are corrected in place. The fourth - `PROD-READINESS-4.md:376-381`, `peakConcurrency=3` twice and *"**The peak is 3, not the 5 predicted** - 3 is what the executor actually interleaved, and the number recorded is the measured one"* - is verbatim unchanged, and is contradicted by `:568` and `:703` of the same file, which say the peak varied 2-5 and that "Only the pass count is recorded now".
The ledger states at `:810` that "**All four are corrected in place**", and the disposition table records both `REVIEW-3` finding 3 and `REVIEW-6` finding 3 as **fixed**.

**Third, the disposition table built to close `REVIEW-6.md` finding 4 misreports at least five dispositions, and its arithmetic is wrong.**
It claims to account for "every one of the 56 findings across all seven reviews"; its own `findings` column sums to **57**.
`REVIEW-2` finding 9 is listed as **fixed** and the sentence it is about stands verbatim at `:319`.
`REVIEW-6` finding 9 is dispositioned "sweep count restated" and the sweep still says 30 commits, for a branch that now has 37.
`REVIEW-AA92CA7` findings 5 and 8 are carried to `N4-11`, which describes neither, and finding 8's tautology is unchanged in shipped test code.
The prose directly beneath it says "**The two findings this run declines to act on**" and names two findings the table puts in the *carried* column, while fourteen findings sit in the table's `declined` column with no reason given anywhere - including two the ledger's own reviewers measured false and which are still in the ledger.

There is no P1, nothing is fabricated, no production error is hidden, and no regression was introduced.
I considered PASS-WITH-FINDINGS and know that it would end the cycle.
I did not take it because the range's one job was that a finding recorded closed is closed, and the user-facing document is now on its third round of being repaired for a false claim about what the app does - this time contradicted by a measurement any reader of the same ledger page could have run in a minute.

## What I ran

All mutation work was done in one detached worktree I created under my own scratchpad (`wt/rev7`), at `040ecd2`.
It is removed; `git worktree list` now shows only `/Users/<user>/dev/otto`, and it was `git status --porcelain` empty before removal.
No command's `--package-path` pointed into the main tree; `verify.sh` ran from my worktree and clones itself into its own temp directory.
I made no commit, ran no network command, touched no physical device, touched nothing in `<backup-dir>`, ran no `git checkout --` in the main tree, and deleted no file I did not create - the two probe files I added inside the worktree I deleted myself.
Every mutation was applied by a script that printed the exact text it removed and asserted the occurrence count before writing, and was reverted with `git checkout --` **inside the worktree**, followed by a `git status --porcelain` check.

Host: macOS 15.6.1 (24G90), arm64, Xcode 26.3 (17C529), SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five baseline dimensions, re-measured at `040ecd2`

**1. `./scripts/verify.sh` - exit 0.**

```
== VERIFIED: 040ecd2ceab17b79366f10ba3cc8fdab8918e5e2 builds, tests, and lints from a clean clone
   OttoDomain: 261
   OttoPersistence: 127
   OttoUI: 209
   total: 597 tests
./scripts/verify.sh  182.80s user 39.18s system 166% cpu 2:13.32 total
```

Ledger's `f51d5ed` row: `exit 0, 261 / 127 / 209 = 597`. **Exact match.** Baseline `2d8913c` was 589.

**2. `swiftlint --strict`, standalone - exit 0.**

```
Done linting! Found 0 violations, 0 serious in 225 files.
```

Ledger: `clean, 225 files`. **Exact match.**

**3. Simulator suite, from `Packages/OttoUI/` - exit 0.**

```
✔ Test run with 119 tests in 22 suites passed after 4.515 seconds.
✔ Test run with  72 tests in 12 suites passed after 0.062 seconds.
✘ Test run with  53 tests in  9 suites passed after 3.261 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Ledger: `119 / 72 / 53 = 244`, 7 known issues. **Exact match**, and +1 over `REVIEW-6.md`'s 52, which is the one test this range adds.
All seven known issues are `EmptyStateTests` accessibility assertions, as ASSUMPTION 7 states; this host vends no AX tree.

**4. Non-Gregorian harness - 1 / 1 / 5, the same five citations, 209 tests.**

Bundle path absolute, run from my worktree root, per `CalendarEraTests.swift`'s header.

```
th_TH@calendar=buddhist          1 issue   209 tests in 38 suites failed after 15.939 s
    DisplayFormattingTests.swift:49:9   ("Aug 15, 2569 BE")  == "Aug 15, 2026"
ja_JP@calendar=japanese          1 issue   209 tests in 38 suites failed after 10.705 s
    DisplayFormattingTests.swift:49:9   ("Aug 15, Reiwa 8")  == "Aug 15, 2026"
ar_SA@calendar=islamic-umalqura  5 issues  209 tests in 38 suites failed after 10.210 s
    DisplayFormattingTests.swift:49:9   ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
    DisplayFormattingTests.swift:59:9   ("Every ٤٥ days")     == "Every 45 days"
    DisplayFormattingTests.swift:68:9   ("١ subscription")    == "1 subscription"
    DisplayFormattingTests.swift:69:9   ("٣ subscriptions")   == "3 subscriptions"
    NotificationReconciliationTests.swift:170:9  ("… on Rab. I 12.") == "… on Aug 25."
```

Identical to `reviews-4/BASELINE-4.md` and to `REVIEW-6.md`. **Unchanged.**

**5. Flake rate - 12 of 12.**

`swift test --package-path Packages/OttoUI`, twelve consecutive unmutated runs in my clean worktree at `040ecd2`:

```
run  1 rc=0 ✔ 209 tests in 38 suites passed after 15.982 s
run  2 rc=0 ✔ 209 …  12.432 s     run  8 rc=0 ✔ 209 …  10.353 s
run  3 rc=0 ✔ 209 …  12.974 s     run  9 rc=0 ✔ 209 …  11.333 s
run  4 rc=0 ✔ 209 …  12.331 s     run 10 rc=0 ✔ 209 …  11.981 s
run  5 rc=0 ✔ 209 …  11.132 s     run 11 rc=0 ✔ 209 …  10.927 s
run  6 rc=0 ✔ 209 …  10.616 s     run 12 rc=0 ✔ 209 …  10.402 s
run  7 rc=0 ✔ 209 …  10.688 s
SUMMARY pass=12 fail=0
```

**12 of 12.** Spread 10.4 s - 16.0 s, narrower again than `BASELINE-4.md`'s 15.5 - 126.4 s, on a host with nothing else of mine running; this is the known cause and not a finding.
`SyncActivationServiceTests` (`N4-13`) did not fire in any of my 18 host runs.

### Per-commit build sweep - every commit in the range, all three packages

`swift build --build-tests --package-path Packages/<pkg>` in my detached worktree, detaching onto each of the 5 commits in turn: **15 of 15 OK, 0 failed.**

```
a9144c7  3ec68e2  faa0313  f51d5ed  040ecd2
```

### Falsifications

Each printed the exact text it removed and asserted the occurrence count was 1 before writing; each was reverted and `git status --porcelain` confirmed empty afterwards.

| # | what I broke | ledger records | I measured |
|---|---|---|---|
| M1 | the `catch`-branch generation guard removed (`AppModel+Export.swift:100-102`) | "**1 issue**, `(.failed(...)) == .notPrepared`" | **1 issue** ✅ `SettingsExportWithdrawalTests.swift:192:9`, `(.failed("…SnapshotRefused…")) == .notPrepared`; `** TEST FAILED **`, rc 65 |
| M2 | pass-end call site reverted to the pre-fix interpolation (`OttoLog.swift:178`) | R4-3 guarded | **2 issues** ✅ `SchedulingLogTests.swift:203` (the pinned line) and `:209` (the new `allSatisfy`) |
| M3 | the test's own pass retagged `.significantTimeChange` → `.foreground` (`SchedulingLogTests.swift:161`) | pin is load-bearing | **1 issue** ✅ `SchedulingLogTests.swift:199:27`, `lines.last { … "pass end trigger=significantTimeChange" } → nil`, in the **full** 209-test process |
| M4 | `plausibleStoredDayYearsBehind` 70 → 100 (round 3's symmetric century) | asymmetry guarded | **17 issues** ✅ across `indianIsCaughtByTheAsymmetry` (13, incl. the new month loop at `:168`), `windowEdges` (3), `knownUncatchable` (1) |
| M3+S | M3 **plus** a sibling test driving real trigger-tagged `.significantTimeChange` passes for six seconds | not claimed | **green**, `✔ 6 tests in 2 suites passed` - see finding 5 |

### Probes I wrote (in my worktree, deleted with it)

**A. `docs/next-wave.md:31` driven through the real `NotificationScheduler`.**
One subscription per run, `today = 2026-08-11`, `SchedulerFixture`, indices 9001+, counting the `FakeNotificationClient`'s pending requests.

```
ZZDOC indian-anchor    implausible=[1948-08-15] effective=active scheduledCount=4 pending=4 ledgerFailures=1
      ids=[…9001|2026-08-12|renewal, …|2026-09-12|renewal, …|2026-09-25|usageCheckIn, …|2026-10-12|renewal]
ZZDOC japanese-anchor  implausible=[0008-08-15] effective=active scheduledCount=4 pending=4 ledgerFailures=1
ZZDOC buddhist-anchor  implausible=[2569-08-15] effective=active scheduledCount=0 pending=0 ledgerFailures=1
ZZDOC buddhist-lastUsed implausible=[2569-05-01] effective=active scheduledCount=3 pending=3 ledgerFailures=1
      ids=[…9004|2026-08-17|renewal, …|2026-09-17|renewal, …|2026-10-17|renewal]     (no usageCheckIn)
ZZDOC healthy          implausible=[]           effective=active scheduledCount=4 pending=4 ledgerFailures=0
      ids=[… renewal x3, …|2026-10-28|usageCheckIn]
```

**B. Whether the affordance the document names is on screen.**

```
ZZDOC usage paused-buddhist effective=paused    usageSectionRendered=false implausible=[2569-04-01, 2569-05-01]
ZZDOC usage trial-buddhist  effective=trial     usageSectionRendered=false implausible=[2569-04-01, 2569-05-01, 2569-05-15]
ZZDOC usage cancelled       effective=cancelled usageSectionRendered=false implausible=[2569-04-01]
```

`usageSectionRendered` is `effectiveStatus(asOf:) == .active`, which is `UsageSectionView`'s entire visibility condition (`PauseFlowView.swift:164`).

## Findings

### 1 - P2. `docs/next-wave.md`'s new closing sentence is false, and the ledger's own carried finding says so

**Evidence.** `docs/next-wave.md:31`, added by this range:

> **Every repair above is something you do in the app, on purpose.** None of them can be prompted by a notification, because a subscription with any corrupt day schedules no reminders at all - which is the whole reason this page exists rather than a banner.

Measured through the real `NotificationScheduler`, probe A: a subscription whose `implausibleStoredDays` is non-empty is scheduled **4** notifications for an Indian/Saka anchor, **4** for a Japanese one, and **3** for a Buddhist `lastUsedDate`.
The gate at `NotificationScheduler.swift:234-244` skips only `reconcileLedger` - billing-event materialization.
The notification plan is built at `:120-131` from `live.flatMap { reminderSchedule(…) }` with no plausibility filter at all, so a *backward*-offset corruption leaves an anchor in the past, which the planner rolls forward, and the pass schedules the result.
Only a *forward*-offset corruption (Buddhist `+543`, Hebrew `+3760`) pushes every rung past the horizon and yields zero.
By the offsets tabulated in `StoredDayPlausibility.swift:47-53`, that is 2 of the 11 calendars the rule detects; the other 9 schedule.

`PROD-READINESS-4.md:663`, `N4-2`, carried at **P2** in the same file this range edited:

> For every **negative**-offset calendar the planner still produces rungs from the corrupt anchor and the pass still schedules them. Measured at round 3's HEAD: Japanese, Minguo, Islamic and Persian each schedule **4 reminders on the wrong days** … So the state closed for those calendars is "wrong reminders, disclosed", not "no reminders".

The same sentence is asserted in the ledger's own remediation bullet at `:808`: *"the section closes with the general form: every repair here is something you do in the app on purpose, **because a subscription with any corrupt day schedules no reminders at all**"*.

**Why this is P2 and not P3.** This document is the run's only mitigation for a population it cannot otherwise reach, and its heading still asserts *"**The repair is manual, it works**"* (`:9`).
The concrete harm is not the missing repair - the advice "do it in the app on purpose" is correct - it is the *reason*: an Indian/Saka or Japanese user who is visibly receiving Otto reminders now has a written statement that a corrupt subscription schedules none, from which the correct inference is "this page is not about me".
That is the population round 4 spent stage 2 making detectable, and their reminders are firing on the wrong days.
`reviews-4/REVIEW-2.md` finding 3 was P2 for this document naming an impossible step; `reviews-4/REVIEW-6.md` finding 1 was P2 for the same document naming a second one; this is the third rewrite and the third false statement in it.
The ledger's `## EVERY UNVERIFIED FIX, AND WHY` table closes with *"Nothing else in this run is verified only by reading"*, and this sentence is verified only by reading.

**Why the builder missed it.** The remediation was driven off `REVIEW-6.md`'s finding, which was about one row and one field, and it verified that row against the planner properly - every number in `:27` reproduces.
It then generalised from one measured case (`lastUsedDate` suppresses the check-in) to a claim about the whole scheduler, and generalisations are the one thing in this range that got no measurement.
`grep -n "N4-2" PROD-READINESS-4.md` would have refuted it in one command, in the file being edited.

### 2 - P2. `REVIEW-6.md` finding 3's fix stops one row short of the table it was given, and the ledger says it did not

**Evidence.** `reviews-4/REVIEW-6.md` finding 3 tabulated four surviving statements. Three are corrected in this range:

| `REVIEW-6.md` row | state at `040ecd2` |
|---|---|
| ITEM 4's body, "does not reproduce" | **corrected** at `:400-405` |
| `NOT DEFECTS` F10 row, "peak concurrency 3" | **corrected** at `:568` |
| `N4-3` at P3, overlap "not established" | **corrected** at `:664`, raised to P2 |
| `:372-373` `peakConcurrency=3` twice and `:377` "The peak is 3, not the 5 predicted" | **unchanged**, now `:376-377` and `:381` |

At `040ecd2`, `PROD-READINESS-4.md:376-381` reads:

```
five triggers                  passes=5  peakConcurrency=3
a trigger during a pass        passes=4  peakConcurrency=3
```
> **The peak is 3, not the 5 predicted** - 3 is what the executor actually interleaved, and the number recorded is the measured one.

It is contradicted twice in its own file: `:568` (*"the peak concurrency varied 2-5 across runs and is a property of the executor, not of the code"*) and `:703` (*"The reviewer measured 2, 5, 3, 3 - including the 5 my sentence said had not happened … Only the pass count is recorded now"*).
`:381` is the sentence `reviews-4/REVIEW-3.md` finding 3 was raised about, and it is the strongest form of the claim - it presents a one-sample figure as measurement discipline working.

The ledger asserts the opposite at `:810`: *"All four are corrected in place."*
The disposition table at `:826` records `REVIEW-6` finding 3 as **fixed**, and at `:822` records `REVIEW-3` finding 3 as **fixed**.

**Why this is P2.** `PROD-READINESS-4.md:702` names this class as the run's worst defect, and `:810` names the structural cause correctly - an appended ledger leaves the corrected sentence where a reader meets it first.
Having named the cause, the range applied the fix to three of the four instances a reviewer had already located by line number, and then recorded all four as done.
A round-5 reader opening ITEM 4 reads the refuted number as the run's finding; a round-5 reader opening the disposition table is told it was corrected.

**Why the builder missed it.** The remediation bullet was written from the reviewer's *prose* summary, which named three concurrency surfaces, rather than from the reviewer's *table*, which named four.
The prose paragraph and the table disagree in `REVIEW-6.md` itself, and the shorter one was used.

### 3 - P2. The disposition table misreports at least five dispositions, and its arithmetic is wrong

**Evidence.** `PROD-READINESS-4.md:816-828`. Legend: *"**Fixed** means a guard bites; **carried** means it is in NEXT ROUND with its measurement; **declined** means it is answered and not acted on."*

**(a) The count.** `:818` says *"Seven reviews, 56 findings"* and `:812` says the table accounts for *"every one of the 56 findings"*.
I counted the `### N` headers in each review: REVIEW-1 **9**, REVIEW-2 **10**, REVIEW-3 **5**, REVIEW-4 **10**, REVIEW-5 **6**, REVIEW-AA92CA7 **8**, REVIEW-6 **9**. Total **57**, which is also what the table's own `findings` column sums to.

**(b) `REVIEW-2` finding 9, listed as fixed, is unchanged.**
That finding is that `"the rule newly rejects only 1900-01-01 to 1955-12-31"` names the wrong set - the *newly* rejected days are `1926-01-01 .. 1955-12-31`, since `abs(y-2026) <= 100` already rejected 1900-1925.
At `040ecd2`, `PROD-READINESS-4.md:319` still reads *"the rule newly rejects only 1900-01-01 to 1955-12-31"*. `grep -n "1926" PROD-READINESS-4.md` returns four lines, none of them a correction of it.
It is also a record finding, for which "a guard bites" cannot be the disposition.

**(c) `REVIEW-6` finding 9, dispositioned "sweep count restated", is not restated.**
`:794` still says *"Every one of this run's **30** commits builds all three packages"* and `:797` still prints `SWEEP: 30 building, 0 non-building, 30 commits`.
`git log --format=%h 2d8913c..040ecd2 | wc -l` is now **37**. `grep -n "sweep\|SWEEP"` over the ledger finds no restatement anywhere.

**(d) `REVIEW-AA92CA7` findings 5 and 8, carried to `N4-11`, are described by `N4-11` in neither case.**
`N4-11` (`:679`) is *"a sibling's canary masks a deleted canary, wherever tests share a log window"* - which is `REVIEW-AA92CA7` finding **4**, and finding 4 is correctly filed there.
Finding 5 is that the canary is emitted at a lower level than the line it vouches for and its failure message overstates what it knows.
Finding 8 is a tautological assertion, and it is unchanged in shipped code at this head: `SchedulingLogTests.swift:114` selects on `$0.hasPrefix("reconcile failed=[")` and `:121` then asserts `#expect(line.contains("failed=["))`.
Both are recorded as carried under an entry that does not carry them.

**(e) The prose under the table contradicts the table.**
`:828`: *"**The two findings this run declines to act on, and why:**"*, followed by `REVIEW-4` finding 9 and `REVIEW-2` finding 10.
The table puts both of those in the **carried** column (`9 → N4-14`, `10 → N4-13`), not the declined one.
The declined column actually holds fourteen findings - REVIEW-1 9; REVIEW-2 1, 5, 6; REVIEW-3 5; REVIEW-4 2, 5, 6, 7; REVIEW-5 4; REVIEW-AA92CA7 6, 7; REVIEW-6 4, 9 - and twelve of them are given no reason anywhere in the ledger, against the table's own definition of "declined" as *"answered and not acted on"*.
Two of the silently declined are sentences a reviewer measured false and that are still in the ledger: `:147`, which states as shipped a footer sentence the tree replaced (`REVIEW-4` finding 5, and `:352` of the same file says the first sentence was wrong), and `:153`'s *"all of them were"* (`REVIEW-4` finding 6).
`REVIEW-AA92CA7` finding 7 is also silently declined: `grep -n "R0-2\b" PROD-READINESS-4.md` returns nothing, so a round-1 P2 is still in no terminal state, against the ledger's own contract at `:57` (*"Terminal states are **RESOLVED** … **DEFERRED** … or **REJECTED TWICE** … There are no others"*).

**Why this is P2 and not a pile of P3s.** This table is not incidental record-keeping - it is the whole of the answer to `REVIEW-6.md`'s finding 4, offered at `:812` as *"the only form of that claim worth making"*.
A completeness artifact whose value is that a later round can trust it, and which misreports five of the first ten dispositions I checked, is worse than the absence it replaced: it converts "not read" into "recorded as handled".
Every one of (b), (c) and (d) is checkable with a single `grep` against the artifact the row cites.

**Why the builder missed it.** The table was written from the remediation sections - which is where each finding was *answered* - rather than from the reviews' finding lists and the ledger's current text.
That is the same inheritance error `REVIEW-AA92CA7` finding 7 diagnosed for round 2's carry-forward table, reproduced by the table built to prevent it.

### 4 - P3. The `lastUsedDate` repair the document names is unreachable unless the subscription is effectively active

**Evidence.** `docs/next-wave.md:27` now says, without qualification:

> Open the subscription and tap **I used this today**, in the Usage section of its detail screen.

`UsageSectionView` renders that button inside `if subscription.effectiveStatus(asOf: model.subscriptionsStore.today) == .active` (`PauseFlowView.swift:164-175`), and it is the only in-app control that calls `recordUsage` (`:172` → `AppModel.swift:191` → `SubscriptionFlowService.swift:148`).
Measured, probe B: a paused subscription with a Buddhist-corrupt `pauseEndsOn` derives to `.paused`, a trial with a Buddhist-corrupt start derives to `.trial`, and a cancelled one to `.cancelled`.
In all three the Usage section - and therefore the named button - is not on screen, while `implausibleStoredDays` names the corrupt `lastUsedDate` in the log line the document tells the user to read.

The document's own closing sentence contemplates exactly this case - *"a paused or never-used subscription may need the second and third rows above as well as the first"* (`:29`) - so paused subscriptions are in scope, and the ordering the user needs (resume first, then record use) is stated nowhere.
`:27` also says the button is *"the only control that writes this field"*; `NotificationActionHandler.swift:159` is a second writer, which the row's own next sentence tells the user not to rely on.

**Severity P3, not P2.** The dominant case is an active subscription, and there the step is correct, reachable and repairs the field - I confirmed `recordUsage`'s guard (`lastUsedDate != today`) does not block a 2569 value.
This is the residue of `REVIEW-6.md` finding 1 rather than a recurrence of it.

**Why the builder missed it.** The fix was derived by finding the writer and then finding the view that calls it. `PauseFlowView.swift:171` is the right line; `:164`, seven lines above, is the condition under which it exists, and nothing in the remediation asks whether the population with the corrupt field satisfies it.

### 5 - P3. The R4-3 pin relocates the shared-window hazard rather than removing it, and the guarantee is scoped to the wrong unit

**Evidence.** `SchedulingLogTests.swift:193-201` replaces the unpinned `"pass end trigger=foreground"` selector with `"pass end trigger=significantTimeChange"`, on the stated ground that *"`.significantTimeChange` appears nowhere else in OttoServicesTests"*.

The claim is true as written, and the pin is live: M3 alone fails at `:199`, in the full 209-test process.
It is still a presence assertion over a shared window, satisfiable by a line the test did not produce.
Checked against a population I built: M3 **plus** one temporary sibling in the same target driving real trigger-tagged `.significantTimeChange` passes for six seconds:

```
✔ Test "⛔ a skipped subscription's line names the offending days, …" passed after 12.381 seconds.
✔ Test run with 6 tests in 2 suites passed after 12.381 seconds.
```

The new `allSatisfy` at `:209` does not help here - it ran against the sibling's lines, which all carry the field.

Two things make the residue worth recording rather than shrugging at.
The guarantee is scoped to *the target*, and the window is scoped to *the process*: `OSLogStore(scope: .currentProcessIdentifier)` (`:216`), and under `swift test` SwiftPM links every test target of this package into one `OttoUIPackageTests.xctest` and runs them together, so `NotificationCoordinatorTests.swift:220` - which does use `.significantTimeChange`, in OttoUITests - is inside the same window today and is harmless only because it drives a `SchedulerSpy` rather than the real scheduler.
And nothing enforces the uniqueness: a future test that reaches the real scheduler with this trigger silently disarms the presence half, and no assertion fails when it does.
This is `N4-11` - which this run coined, at `:679` - still live in the range's own new assertion, one trigger name further along.

**Severity P3.** The R4-3 *regression* stays caught either way: under M2, a sibling's pass-end line lacks `truncatedAfter=` too, so both `:203` and `:209` fail. Only the presence half (M3's shape) is maskable, and today nothing masks it.

**Why the builder missed it.** The reviewer's demonstration was that a *foreground* sibling masked a foreground assertion, so the fix answered "which trigger has no siblings" rather than "what makes this assertion independent of siblings" - which needs an identifier the test owns, `--filter`, or a suppressed subsystem, exactly as `N4-11`'s own text says.

### 6 - P3. `N4-12` says the "~80 ms" figure is corrected where round 4 cites it, and round 4's own ledger still cites it

**Evidence.** `PROD-READINESS-4.md:687-688`, written inside this range by `a9144c7`:

> **N4-12 (P3) - the "~80 ms" window figure is wrong by about 180x and is load-bearing in five files.** … Corrected where round 4 cites it; the four round-3 citations are untouched, because editing them is not this run's scope.

`grep -rn "80 ms"` at `040ecd2` finds five surviving citations: `SchedulingLogTests.swift:92`, `BoundaryLogTests.swift:77` and `:109`, `MappingLogPrivacyTests.swift:91` - the four round-3 ones, correctly disclosed - **and `PROD-READINESS-4.md:445`**, which is round 4's own text and reads *"`OSLogStore.position(date:)` reaches ~80 ms behind `since`"*.
`UnreportableInvalidationTests.swift:133` is the round-4 citation that *was* corrected, to 15.30 / 12.66 / 15.12 s.

**Severity P3**, because the ledger's figure misleads no test. Recorded because it is a third instance of the pattern finding 2 is about, in a carry-forward entry authored in this range to describe that very pattern, and because `:445` is the sentence that justifies a pinning decision a later round is meant to reuse.

### 7 - P3. The ledger's `REVIEW RANGES` table names `f51d5ed` as this stage's reviewed head; the head is `040ecd2`

**Evidence.** `PROD-READINESS-4.md:74`:

> \| 6r - the REJECT's remediation \| `92174e4..f51d5ed` \| `f51d5ed` \| (`reviews-4/REVIEW-7.md`, a **different** reviewer) \|

The range I was issued is `92174e4..040ecd2`, and the branch tip is `040ecd2`.
`faa0313` and `040ecd2` are therefore in no range that table declares, and the table's own contract at `:70` - *"Each later stage's range starts at the previous stage's **reviewed head**"* - would start round 5 at `f51d5ed` and skip both.
Both are `PROD-READINESS-4.md` / `reviews-4/` only, so nothing executable is skipped; the same shape as `REVIEW-6.md` finding 9, materially true and formally wrong.

Recorded because `N3-4` - *"`aa92ca7` outside every review range"* - is marked **CLOSED** at `:647` with the reason *"The wording that produced the gap is fixed in this run's REVIEW RANGES section"*, and the fixed section reproduces the gap two rows below. `:76` states the intent correctly: *"Leaving them outside a range would reproduce N3-4 … inside the run that closed it."*

## Explicit checks

- **Fabricated or unreproducible findings.** One claim in the range does not reproduce and is refuted: `docs/next-wave.md:31` (finding 1). Everything else the range measures reproduces, including several I expected not to - the `catch`-guard falsification at 1 issue on the named assertion, the R4-3 pin at 1 issue, the interpolation revert at 2, the plausibility revert at 17, the simulator arithmetic at 119 / 72 / 53, and every number in the rewritten `lastUsedDate` row (90-day cadence at `ReminderSchedule.swift:218`; zero check-ins planned for the corrupt fixture against one for the healthy one, measured).
- **Citations that do not say what they are claimed to say.** Five. `:319` ("newly rejects", carried over uncorrected and recorded as fixed), `:147` (footer copy the tree replaced), `:153` ("all of them were"), `N4-11` cited for two findings it does not describe, and `N4-12`'s "corrected where round 4 cites it" against `:445`. The citations that carry this range's own load hold: `PauseFlowView.swift:171` really is the button, `SubscriptionDetailView.swift:108` really hosts it, `ReminderSchedule.swift:228` really is the `reference` line, and `BillingEventRepository.swift`'s new contract matches `OttoStore+BillingEvents.swift:155-225` exactly, including that the save keys on `mutated`.
- **Severity inflation or deflation.** No inflation. One deflation by omission: the disposition table's `declined` column carries twelve findings with no recorded reason (finding 3e), among them two ledger sentences a reviewer measured false, which reads as a disposition rather than as an unanswered item.
- **Features smuggled past the no-features rule.** None. Nine files: one ledger, one review file, one permitted doc, two comment-only production files, one production file whose only change is a blank line, and three test files. No new API, no new copy in the app, no navigation, no `UserDefaults` key, no dependency. `.swiftlint.yml`, `.github/`, every `Package.swift`, `project.yml`, `PROD-READINESS{,-2,-3}.md`, `DECISIONS.md`, `README.md`, `reviews/`, `reviews-2/`, `reviews-3/` and every `docs/` file except `next-wave.md` are untouched.
- **Any SwiftData schema change.** None. The only `Packages/OttoPersistence/Sources/` file in the diff is `BillingEventRepository.swift`, and `git diff … | grep -vE '^[+-]\s*///'` over it returns **zero** non-comment changed lines. No `Stored*`, no `OttoSchemaV*`, no `OttoMigrationPlan`, no `@Model` / `@Attribute` / `@Relationship` in the diff. V3 stays frozen.
- **Prohibited actions.** None observed. `git show-ref` puts `refs/heads/main` and `refs/remotes/origin/main` both at `406a5a6`, so nothing was pushed or merged; `.git/FETCH_HEAD` does not exist; `git tag` is empty; `92174e4` is still an ancestor of `040ecd2`, so no history was rewritten; no commit was created by me. `.swiftlint.yml` is untouched - no rule relaxed, disabled, re-thresholded, and no `excluded:` path added - and `--strict` is clean over 225 files, so nothing was made to pass by widening a rule.
- **No test weakened.** `git diff 92174e4..040ecd2 -- Packages/ | grep '^-' | grep -E '#expect|#require'` returns exactly **2** lines, both in `StoredDayPlausibilityTests.swift`, and both replaced by strictly stronger forms: the two-literal comparison becomes a function applied to the same constants (it can now fail, and M4 proves the file bites), and the single-offset month loop becomes a two-offset one. **12** assertions added. No `withKnownIssue`, `.disabled`, `.enabled(if:)`, `XCTSkip` or `swiftlint:disable` anywhere in the diff.
- **Fixes that relocated a bug rather than removed it.** One, finding 5: the R4-3 presence assertion moved from a trigger with siblings to a trigger without them, and is still satisfiable by a sibling's line. One cosmetic near-miss: `AppModel+Export.swift`'s doc-comment split is exactly the blank line `REVIEW-4` finding 8 asked for, and it leaves a `///` block at `:27-32` describing `prepared`, which lives in another file, in the leading trivia of `ExportAvailability` alongside that type's own doc comment. It is what the reviewer specified, it lints clean, and I record it only so a later round does not read it as a new defect.
- **Error handling that hides errors.** Nothing new. The range adds no production error path; the `catch`-branch guard it now tests still rethrows unchanged, and narrows only what is *recorded* for a superseded generation.
- **Verification that does not exercise the changed path.** One: `docs/next-wave.md:31`, which is a claim about the scheduler's behaviour that nothing executed before it shipped (finding 1). The row above it at `:27` *was* verified against the planner, correctly and in detail.
- **Tests that pass for the wrong reason.** None found in the range's new tests. The new export test fails at its own final assertion under M1 rather than at a setup step, and it drives the shape (superseded, then failed) that no prior test produced. Five mutations, each failing at an assertion that names what I broke.
- **Flaky or environment-dependent tests, especially over a shared log window.** No flake observed - 12 of 12 on OttoUI, two full simulator runs, three harness locales, all with identical counts. Three assertions in this range read a shared window. `:199`'s pin is checked above (finding 5). `:209`'s `allSatisfy` is new cross-test coupling that cannot currently fail, since one composer produces every `pass end` line; it is non-vacuous only because the `#require` above it guarantees at least one line. The `.significantTimeChange` retag at `:161` does not weaken the test it sits in - the same production entry point, the same pass, the same window.
- **A further `OSLogStore`-reading test.** **None added.** The count stays at ten. The R4-3 emission guard stays inside the query `SchedulingLogTests` already opens.
- **Anything marked resolved without an artifact.** Finding 1 (a P2 recorded closed on a rewrite whose new general claim nobody executed), finding 2 (three of four corrections applied, four recorded), and finding 3 (five dispositions recorded that did not happen).
- **Every commit in the range builds all three packages.** Yes - 15 of 15 across 5 commits.
- **Falsifications broke the thing the finding is about.** Every mutation touched the production line the finding names, the production call site, or the test's own entry point into production - never a proxy. Each printed the removed text and asserted its occurrence count was 1 before writing. The one presence assertion I attacked over a shared window (finding 5) was checked against a sibling population I wrote myself.

## What I could not check, and why

- **That a user can perform the `docs/next-wave.md` repair on a device.** Findings 1 and 4 are established by execution against the real scheduler and by reading every affordance's visibility condition. I did not boot a simulator with a corrupt database and tap through the detail screen; what I measured is that the corrupt subscriptions still schedule notifications, and that the named button's visibility condition excludes three effective statuses.
- **That a human tapping the export row produces a file.** Unchanged and correctly carried as `N4-1`. The closure at `SettingsView.swift:212-216` is reachable by no test this project can run.
- **Release configuration.** Debug only; `verify.sh` builds the app target unsigned for a generic simulator destination. ASSUMPTION 3 carries.
- **A physical device**, and therefore the file protection class on exports left in `tmp`, real `BGAppRefreshTask` behaviour, and whether either real user is on a non-Gregorian calendar. Prohibited this run; ASSUMPTION 1 carries.
- **The `OSLogStore` readers on a CI runner.** Unchanged CANNOT ASSESS. All ten passed here, in `verify.sh`, in all twelve flake runs and in every harness locale, with no canary firing.
- **Whether the concurrent passes `N4-3` / `N4-7` measure actually corrupt anything.** Unchanged by this range and correctly carried.
- **The merits of the fourteen findings in the disposition table's `declined` column.** I checked the disposition claimed against the artifact for `REVIEW-2` 9, `REVIEW-3` 3, `REVIEW-4` 5 and 6, `REVIEW-AA92CA7` 5, 7 and 8, and `REVIEW-6` 1, 2, 3, 7, 8 and 9. I did not re-litigate the rest on their merits; finding 3 is about the record, not about whether declining was right.
- **Whether my flake batch and the baseline's are comparable.** Mine ran on a quiet host and is much faster (10.4 - 16.0 s against 15.5 - 126.4 s). Pass/fail is comparable; wall time is not.
- **The K=31 figure.** Correctly carried as `N4-15` with all three measurements and the reason none of them settles it. I did not re-derive a fourth.
