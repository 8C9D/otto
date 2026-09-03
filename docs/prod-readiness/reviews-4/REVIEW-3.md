# REVIEW-3 - stage 3, item 4 (F10), range `00cb0f1..54bb611`

Reviewed head `54bb611b13271375f7e5b0530a10a3a5e936df58`, branch `prod-readiness-4/2026-08-12`.
The range contains exactly one commit, `54bb611`, touching four files.
All mutation work was done in two detached worktrees I created under my own temp path; the repository working tree was never modified except to write this file.

verdict: PASS-WITH-FINDINGS

## Summary

**The coalescing logic is correct, and I could not break it.**
I falsified it five ways - the builder's four, whose recorded issue counts (5 / 1 / 2 / 1) reproduce exactly, plus one of my own aimed at the wiring line rather than the loop - and every mutation was caught by a shipped assertion.
The ordering invariant the change rests on holds under analysis and under test: `queued` is cleared before the pass and read after it, both inside the same `@MainActor` step, so there is no window in which a trigger is both wiped and unobserved.
A trigger that arrives before the pass body starts is wiped, and that is right rather than a drop, because the pass has not yet read the store.
The gate reopens after a pass that throws, after a pass that is coalesced into, and after the chain drains; I probed the first of those, which no shipped test covers.
There is no deadlock path, no leaked task and no unbounded queue, and nothing in the production wiring can re-enter `rescheduleSoon` from `onOutcome`, which is the only way the loop could spin forever.
Every gate reproduces at the reviewed head, including the simulator counts the commit message predicts to the digit.
The file split is real, necessary and behaviour-preserving, and I proved all three rather than taking the claim.

**What is not sound is the account of what remains.**
The stage marks F10 RESOLVED on the strength of removing concurrency between the coordinator's six triggers, and then makes one measured claim about the concurrency it did not remove - that the background pass and a foreground pass "run one after the other at peak 1" - which is false.
Reproducing the shipped test's own scenario 60 times per run, four times over, the two passes genuinely overlap in about one run in six.
The assertion the builder wrote, measured, and deleted as unreproducible is in fact true 18 % of the time, and it is the F10 defect itself, still live.
Separately, a third entry point into the same race - `NotificationStatusStore.reschedule()`, which every create, edit, delete and reminder-time change goes through - is ungated and is named nowhere in the ledger, the commit message or the source, while a shipped test fires `.stateChange` through the gate that trigger never actually reaches in production.
Neither of those is a regression and neither is a defect in the diff; both are the difference between what the stage fixed and what its record says it fixed.

## What I ran

All measurements at `54bb611` unless stated.
Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five baseline dimensions, re-measured

| dimension | `reviews-4/BASELINE-4.md` at `2d8913c` | measured here at `54bb611` | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0; 258 / 124 / 207, total 589 | **exit 0**; OttoDomain **261**, OttoPersistence **124**, OttoUI **208**, total **593** | +4, all from stages 1-2; matches the commit message's "Host 261/124/208" |
| `swiftlint --strict` | 0 violations, 220 files | **0 violations, 0 serious in 222 files** | clean; matches "clean over 222 files" |
| simulator suite, from `Packages/OttoUI/` | 117 / 72 / 36, 7 known issues | **118 / 72 / 44**, `with 7 known issues`, `** TEST SUCCEEDED **`, exit 0, three consecutive full runs | exact match to the commit message's prediction |
| non-Gregorian harness | 1 / 1 / 5, five named citations | **1 / 1 / 5**, the same five citations | exact |
| flake rate, 12 x `swift test --package-path Packages/OttoUI` | 12 of 12 | **12 of 12 passed, 0 failed**, 208 tests each, 13.3 s - 37.8 s | clean |

The three full simulator runs were byte-identical in their counts (118 / 72 / 44, 7 known issues), and I ran the coordinator suite alone a further ten times across the falsification work.
No new test showed order- or timing-dependence; the four added tests each build their own spy and coordinator and share no state, and swift-testing does interleave them on the main actor, which I observed directly in the probe run.

The flake dimension is worth naming for what it does not cover: `NotificationCoordinator.swift` is inside `#if os(iOS)` and compiles to nothing under host `swift test`, so all twelve runs, and the OttoUI leg of `verify.sh`, exercise **none** of this stage's changed code.
The commit message says so ("none of this compiles on a mac host"); I record it here because it means the simulator suite is the whole of the verification for this stage, which is why I ran it repeatedly.

### Per-commit build sweep

One commit in range.

```
54bb611  swift build --build-tests --package-path Packages/OttoDomain        BUILD OK
54bb611  swift build --build-tests --package-path Packages/OttoPersistence   BUILD OK
54bb611  swift build --build-tests --package-path Packages/OttoUI            BUILD OK
```

### Falsifications

Each mutation printed the exact text removed and asserted the occurrence count was 1 before patching; each was reverted from a saved copy, never with `git checkout`.
Counts are real issues, excluding the 7 known `EmptyStateTests` accessibility issues.

| # | what I broke | ledger says | I measured |
|---|---|---|---|
| F1 | `rescheduleSoon` restored to its exact `00cb0f1` body | 5 issues - passes 5, peak 3, published 5 | **5 issues** - passes **5** ✅, published **5** ✅, peak **2 / 5 / 3 / 3** over four runs ❌ |
| F2 | `next = self.queued` → `next = nil` (coalescing becomes dropping) | 1 issue - the follow-up swallowed | **1 issue**, `passes.count → 1` ✅ |
| F3 | `self.queued = nil` moved to after `next = self.queued` | 2 issues - a spurious second pass | **2 issues**, `passes.count → 2`, `published.count → 2` ✅ |
| F4 | `self.inFlight = nil` deleted (the gate never reopens) | 1 issue - later triggers do nothing | **1 issue**, `passes.count → 1` ✅ |
| F5 (mine) | `queued = trigger` deleted from the early-return branch - the wiring line, not the loop | not claimed | **1 issue**, `passes.count → 1`; the queueing line is pinned |

The reconfirmation block's pass counts also reproduce exactly: five triggers gave `passes=5` and a trigger during a pass gave `passes=4` on every one of four runs.

### Probes I wrote (in my worktree, deleted with it)

| probe | question | result |
|---|---|---|
| A | does the gate reopen after a pass that THREW? | **yes** - two passes; no shipped test covers this |
| B | does a trigger arriving during a FAILING pass still get its follow-up? | **yes** - two passes |
| C | what does cancelling the shared chain do? | inconclusive in this harness - the spy does not honour cancellation; see "could not check" |
| D | 60 iterations of the shipped `theBackgroundPassIsOutsideTheGate` scenario, recording peak concurrency | peak 2 in **11, 11, 13, 10 of 60** across four independent runs (45 / 240 = **18.8 %**) |
| E | 60 iterations of a coordinator pass concurrent with `NotificationStatusStore.reschedule()` | peak 2 in **7, 14, 3, 9 of 60** across four independent runs (33 / 240 = **13.8 %**) |

### The file split, checked rather than accepted

- The stubs block moved out is **identical** to the new file's body after stripping comments and the `private` keyword - verified by normalising both and comparing, not by eye.
- The split was **necessary**: re-inserting the exact 63-line block the diff removed gives a 405-line file, and `swiftlint --strict` then reports `File Length Violation: File should contain 400 lines or less: currently contains 405 (file_length)`, 1 violation in 222 files.
- `.swiftlint.yml` is untouched in the range, and `file_length` and `nesting` are both SwiftLint defaults, so neither was re-thresholded to make this pass.

## Findings

### 1 - P2. The one concurrency claim the stage makes about what it did NOT fix is false, and a true assertion was deleted because of it

**Evidence.**
`PROD-READINESS-4.md:379` (§ITEM 4, "One claim was written, measured, and deleted rather than shipped") and `NotificationCoordinatorTests.swift:267-273` both state: "The obvious assertion, `peakConcurrency == 2`, **does not reproduce**: measured, the two passes run one after the other at peak 1."
I ran exactly the shipped test's scenario - `rescheduleSoon(.foreground)` then `handleBackgroundRefresh(task)`, both awaited - 60 times per execution, four executions:

```
background+foreground peak distribution [(1, 49), (2, 11)]  worst=2
background+foreground peak distribution [(1, 49), (2, 11)]  worst=2
background+foreground peak distribution [(1, 47), (2, 13)]  worst=2
background+foreground peak distribution [(1, 50), (2, 10)]  worst=2
```

The two passes overlap in 45 of 240 iterations.
`NotificationScheduler` is an `actor` (`NotificationScheduler.swift:11`), which is not a defence: `reschedule` suspends at `await client.permission()` before it does anything and again at `try await subscriptions.subscriptions()` before `reconcileLedger` performs its first write, so the actor does not serialise passes - it interleaves them, which is what peak 2 means.
That overlap is F10 itself: two full passes, each loading every subscription, reconciling every ledger and writing every watermark, against the same rows and the same shared `NotificationScheduler` instance (`OttoApp.swift:60-72` passes one scheduler to both the coordinator and the store).

Deferring the fix is defensible and the reason given in the same paragraph, and at `NotificationCoordinatorTests.swift:275-277` ("routing the background pass through the same chain changes what `expirationHandler` cancels"), is a real blast radius.
Recording that the overlap does not happen is not defensible, and it is now written into the source where the next person to touch this file will read it as measured fact.

**Why the builder missed it.** `#expect(peakConcurrency == 2)` fails on any run that scheduled serially, which is 5 runs in 6. A single red run reads as "does not reproduce", and the conclusion was drawn from the failure of a *flaky positive* rather than from a distribution. The same trap the round-4 flake dimension exists to catch, approached from the other side: the builder measured a non-deterministic quantity once and recorded the sample as the property.

### 2 - P2. A third ungated entry point into the same race, named nowhere

**Evidence.**
`NotificationStatusStore.reschedule()` (`Packages/OttoUI/Sources/OttoStores/NotificationStatusStore.swift:43-48`) calls `scheduler.reschedule(now:today:timeZone:trigger: .stateChange)` directly.
It is driven by `AppModel.swift:118` (`subscriptionsStore.onMutation` - every create, edit and delete), `AppModel.swift:134` (`settings.onReminderTimeChange`) and `AppModel.swift:149` (`flowFinished()` - every Wave 5 flow).
It shares the one `NotificationScheduler` instance with the coordinator and never touches `rescheduleSoon`, so the gate cannot see it.
Measured, a coordinator pass and a store pass overlap in 33 of 240 iterations:

```
coordinator+store peak distribution [(1, 53), (2,  7)]  worst=2
coordinator+store peak distribution [(1, 46), (2, 14)]  worst=2
coordinator+store peak distribution [(1, 57), (2,  3)]  worst=2
coordinator+store peak distribution [(1, 51), (2,  9)]  worst=2
```

Nothing discloses this.
`ITEM 4` is marked **RESOLVED** (`PROD-READINESS-4.md:345`) under the framing "Five simultaneous full reschedules ... racing on the same rows" (`:356`), the `rescheduleSoon` doc comment at `NotificationCoordinator.swift:153-161` asserts "Coalesced, not dropped and not queued without bound" with no scope, and the background exception at `:377-381` is disclosed as if it were the only one.
The store path is the most frequent trigger class in ordinary use - it fires on every edit - and it is the one the record is silent about.

Aggravating, and the reason I did not read this as merely "out of scope": `NotificationCoordinatorTests.swift:233` and `:254` fire `rescheduleSoon(.stateChange)`, and `:253` fires `rescheduleSoon(.backgroundRefresh)`.
No production caller passes either value to `rescheduleSoon` - `.stateChange` goes through the store and `.backgroundRefresh` through `handleBackgroundRefresh`.
The suite therefore depicts a gate covering trigger classes it does not cover, which is how a reader would conclude the coalescing is complete.

**Why the builder missed it.** The work-list row scopes F10 to `rescheduleSoon`, and the builder audited the coordinator rather than the callers of `ReminderScheduling.reschedule`. Three call sites of `notifications?.reschedule()` in `AppModel` are one grep away, and the round's own §6.2 trigger list in the coordinator's header comment even names them ("Create/edit/delete and permission-grant triggers run through the store layer") - the sentence is there, and its consequence for the gate was not followed through.

### 3 - P3. `peakConcurrency=3` is one sample of a variable quantity, and the sentence built on it is refuted

**Evidence.**
`PROD-READINESS-4.md:352-353` records the pre-fix reconfirmation as `passes=5 peakConcurrency=3` and `passes=4 peakConcurrency=3`, and `:357` explains "**The peak is 3, not the 5 predicted** - 3 is what the executor actually interleaved, and the number recorded is the measured one."
Restoring the exact `00cb0f1` body and running the same tests four times, I measured peak **2, 5, 3, 3** for the five-trigger case and **2, 2, 2, 3** for the trigger-during-a-pass case.
The pass counts (5 and 4) are stable and reproduce every time; the peak is not a property of the code, and 5 - the number the ledger says did not happen - occurred on my second run.

This is presented as the stage's measurement discipline working ("the measured number, not the predicted one"), which makes the unrepeatability worse than it would be in a bare table.
No shipped assertion depends on it: under the fix `peakConcurrency == 1` is structurally guaranteed, and that is what the tests assert.

**Why the builder missed it.** The number was read off one run and never re-run; nothing in the process re-derives a recorded measurement a second time, which is the same mechanism `reviews-4/REVIEW-1.md` finding 4 identified for item 2's falsification table.

### 4 - P3. Coalesced triggers vanish from the log entirely, and the follow-up is attributed to whichever arrived last

**Evidence.**
The only place a trigger reaches the log is `OttoLog.swift:171` (`pass begin trigger=...`) and `:104` via `passEndFields` (`pass end trigger=...`), both inside the `reschedule(now:today:timeZone:trigger:)` wrapper.
A coalesced trigger never calls that wrapper, so it produces no log line of any kind.
`NotificationCoordinator.swift:165` is `queued = trigger`, an unconditional overwrite, so when several triggers arrive during a pass the follow-up is tagged with the last one and the others leave no trace.
`RescheduleTrigger`'s own doc comment (`OttoLog.swift:139-142`) states the purpose this defeats: "Logged so a later investigation can tell a background wake-up from a foreground open without inferring it from timestamps."

Before this stage, a burst of five triggers produced five `pass begin` lines; it now produces one or two, and which trigger names them is a race.
This is an inherent and acceptable cost of coalescing - it is not a defect in the design - but it is a deliberate reduction in the investigative surface this codebase spends heavily to maintain, and it is disclosed nowhere.

**Why the builder missed it.** The trigger is a pure log tag - it never reaches `reschedule(now:today:timeZone:)` - so "the pass is idempotent, N triggers need one more run" is true of the *work* and hides that it is not true of the *record*.

### 5 - P3, process. At the reviewed head the stage records no measurements and the item is still "pending"

**Evidence.**
`git show 54bb611:PROD-READINESS-4.md` line 49 still reads `| 4 | **F10** | ... | pending |`, and line 67 is `| 3 - item 4 | | | |` - the stage's range and reviewed head were never filled in.
The `## ITEM 4` section that carries every number I was asked to reproduce does not exist at `54bb611`; it was added by `2082b69` ("Record items 4 through 7"), outside my range.
`PROD-READINESS-4.md:63` states the rule this breaks - "every start is recorded **when the stage opens**, not when its verdict lands" - and `:87` states "A stage's reviewed head is the commit that RECORDS its measurements, not its last code commit", which `54bb611` is not.

The consequence is not severe: `54bb611`'s commit message carries the same numbers as the later ledger section, word for word, so the evidence *is* inside the range I was given.
But this is the second stage in a row with the same drift - `reviews-4/REVIEW-1.md` finding 9 recorded it for stage 1 - and it was not corrected between them.

**Recorded in fairness:** the branch advanced by twelve commits while I was reviewing, and six of them are documentation.
As of the tree I finished against, `PROD-READINESS-4.md:49` now reads `**RESOLVED** - stage 3` and `:70` reads `| 3 - item 4 | `00cb0f1..54bb611` | `54bb611` | (reviews-4/REVIEW-3.md) |`, so the row has since been filled in - pointing at this file before it existed.
The finding stands as a statement about the head I was given, not about the tree today.

**Why the builder missed it.** The table is updated when a verdict lands rather than when a stage opens, despite the rule directly above it saying the opposite.

## Explicit checks

- **Fabricated or unreproducible findings; the stage's measured concurrency numbers.** Reproduced. `passes=5` and `passes=4` are exact and stable. `peakConcurrency=3` is not reproducible (finding 3), and the claim that `peakConcurrency == 2` for the background pass "does not reproduce" is itself false (finding 1). All four falsification issue-counts (5 / 1 / 2 / 1) reproduce exactly.
- **Citations that do not say what they are claimed to say.** Checked every citation in the item-4 section and the four new doc comments. All accurate except the two measurement claims above. The `nesting` and `file_length` justifications are accurate and I verified both against SwiftLint. The claim that the stub move is "mechanically identical" is accurate and I verified it by normalised comparison.
- **Severity inflation or deflation.** Deflation, twice: the background overlap is recorded as not happening when it happens 18.8 % of the time (finding 1), and the store-layer entry point is recorded nowhere at all (finding 2). No inflation found.
- **Features smuggled past the no-features rule.** None. The diff is four files: one production file (coalescing only), two test files, one ledger. No user-facing copy, no navigation, no new public API - `rescheduleSoon` was already internal-not-private since R4-2 and its signature is unchanged.
- **Any SwiftData schema change.** None. `git diff --name-only 00cb0f1 54bb611` touches nothing under `Packages/OttoPersistence`; the V3 schema files are untouched; nothing in the diff imports SwiftData.
- **Prohibited actions.** None found. No `.github/workflows/` change, no `.swiftlint.yml` change, no `Package.swift` change, no new dependency, no new config key, no Swift language-mode or SDK change, no reformatting or reorganisation beyond the one justified file split. No test was weakened - the four added tests are new and **no existing assertion was changed or removed**. The shared `SchedulerSpy` was modified, which I checked separately: it gains instrumentation (`live`, `peak`, `duringPass`) and one suspension point (`await Task.yield()`, or the injected body on the first pass), both additive. The five pre-existing tests in the suite keep their exact assertions and passed in all thirteen runs I made. The third simulator bucket is 44 tests against 36 at baseline: +4 from stage 1 and +4 here, none removed.
- **Fixes that relocated a bug rather than removed it.** This is the substance of findings 1 and 2. Within `rescheduleSoon` the bug is removed, not relocated. Across the subsystem it is narrowed from three independent racing entry points to two.
- **Can the coalescing DROP work rather than merge it?** No. The one window that looks like a drop - `self.queued = nil` at the top of the loop wiping triggers that arrived before the body started - is safe by construction: the pass has not yet called `now()`, `today()` or `subscriptions()`, so it will observe every change those triggers describe. Any trigger arriving after that line leaves a follow-up, because `queued` is read after the `await` with no suspension between the read and the loop's exit. F2 and F5 both confirm the shipped tests catch a real drop.
- **Can it deadlock?** No. There is no lock in the path; the only shared state is two `@MainActor` properties; nothing awaits `inFlight` from inside a pass, and `onOutcome` in production is `notifications?.apply(outcome)` (`OttoApp.swift:87-89`), which is synchronous and cannot re-enter `rescheduleSoon`. If it could, the `while` loop would never terminate - that is the one live-lock shape, and the wiring forecloses it.
- **Can it leak a task?** No. `inFlight` is cleared on the only exit from the loop, in the same actor step as the final `queued` read. `[weak self]` plus `guard let self` means a deallocated coordinator ends the chain immediately, and the strong `self` inside the loop keeps it alive only for the chain's duration.
- **Can it leave the gate permanently closed?** No. Probe A shows the gate reopens after a pass that throws (`try?` inside `runPass` means no error escapes the loop), probe B shows a follow-up still runs after a failing pass, F4 shows the shipped test catches a gate that never reopens, and test 3 covers the drained-chain case.
- **Error handling that hides errors.** Unchanged from the pre-F10 shape. `try? await scheduler.reschedule(...)` still swallows the error type and publishes `nil`, which is round 1's F3 contract - the failure is reported, the reason is logged by the trigger-tagged wrapper. The move of that code into `runPass` is verbatim; I diffed it. The one genuinely new silence is finding 4, the coalesced triggers that no longer log.
- **Verification that does not exercise the changed path.** Present but disclosed. `verify.sh` and all twelve flake runs compile none of `NotificationCoordinator.swift` (`#if os(iOS)`). The simulator suite is the entire verification, which is why I ran it three times in full and ten times scoped.
- **Tests that pass for the wrong reason.** I broke what each added test claims to guard. `triggersCoalesce` fails on F1 and F3; `aTriggerDuringAPassIsNotSwallowed` fails on F1, F2 and F5; `theGateReopensAfterTheChainDrains` fails on F4; nothing survived that should not have. The exception is `theBackgroundPassIsOutsideTheGate`, which is honestly labelled characterisation, and whose `passes.count == 2` is true of every run - but see finding 1 for the assertion it should also have carried.
- **Flaky or environment-dependent tests.** None added. Every new assertion is structurally determined under the fix: with the gate in place `passes` and `peakConcurrency` cannot vary. Three full simulator runs and ten scoped runs produced identical results. The flakiness in this stage is confined to the ledger's prose about pre-fix and background behaviour (findings 1 and 3).
- **Anything marked resolved without an artifact.** Nothing was marked resolved at all inside my range (finding 5). The RESOLVED marking added later (`PROD-READINESS-4.md:345`) carries the artifact - a falsification table I reproduced in full - but overstates the scope for the reasons in findings 1 and 2.
- **A further `OSLogStore`-reading test.** None added. The nine reads recorded in `reviews-4/BASELINE-4.md` are unchanged; neither new test file mentions `OSLogStore`.
- **Every commit in the range builds all three packages.** One commit; all three build with `--build-tests`.
- **Later work breaking my range.** No. The branch advanced twelve commits past `54bb611` while I reviewed (`12024ab` .. `80eeb97`), and `git diff 54bb611 HEAD` is **empty** for all three code files in my range - `NotificationCoordinator.swift`, `NotificationCoordinatorTests.swift` and `NotificationCoordinatorStubs.swift` are byte-identical at HEAD. Every later change touching this stage is documentary: the `## ITEM 4` section (`2082b69`), the work-list and range rows (`80eeb97`, `d609790`). All line numbers I cite into `PROD-READINESS-4.md` are against the tree as I finished; the quoted text is the stable reference, because that file moved twice under me mid-review.

## What I could not check, and why

- **Whether the concurrent passes actually corrupt anything.** I proved they overlap; I did not prove harm. The scheduler's own reasoning at `NotificationScheduler.swift:97-114` argues that a *partially executed* pass is safe (idempotent materialisation, watermark written after rows, reconcile is a diff) - it does not argue that two *interleaved* passes are, and the budget arithmetic reads a `pendingRequests()` snapshot that a sibling pass can invalidate. Establishing whether that produces a wrong `scheduledCount`, a double-counted snooze budget or nothing at all needs a fake client that records interleaved reads and writes, which is more work than a review of this diff warrants. Recorded as the open question behind findings 1 and 2.
- **Cancellation of the chain.** The gate now makes several callers share one `Task`, so cancelling it cancels work those callers did not start, and `NotificationScheduler.reschedule` does honour cancellation (`try Task.checkCancellation()` at `:115`). No production caller retains or cancels the returned task - `appDidBecomeActive()`'s result is discarded at `OttoApp.swift:122` and the two delegate paths discard it too - so this is latent rather than live, and my probe could not settle it because the test spy ignores cancellation. Not raised as a finding.
- **Release configuration, a physical device, and any non-Gregorian simulator.** Debug only, simulator only, per this run's constraints and ASSUMPTION 3.
- **Real `BGAppRefreshTask` behaviour.** The background path is driven through the `BackgroundRefreshTask` protocol with a fake; the OS's actual scheduling of a refresh task concurrent with a foreground activation is not observable here, so finding 1's 18.8 % is a statement about the executor on this host, not about field frequency.
- **`git worktree list` does not show only the main tree, and I did not make it do so.** I created two worktrees (`scratchpad/r3/wt` and `scratchpad/r3/wt-flake`), confirmed both clean, and removed both; neither appears in `git worktree list` now. Eleven others remain - `rev2-*` at `00cb0f1`, `rev4/*` at `05ff987`, `rev5/*` at `1a1d23b`, `wt-aa92ca7`, `wt-parent`, `wt-tip` - belonging to the other reviewers and stages running concurrently in this run. Every one of them predates my session or was created outside it. Removing another agent's live worktree is precisely the failure round 3's first reviewer committed, so I left them and am reporting them instead.
- **The main working tree was dirty when I finished, and none of it is mine.** I modified nothing in `/Users/<user>/dev/otto` except writing this file. At the moment I finished, `git status` showed `NotificationCoordinator.swift` and `NotificationCoordinatorTests.swift` modified and an untracked `Packages/OttoUI/Tests/OttoUITests/ZZOverlapProbe.swift`. Reading them, they are the builder's in-progress remediation *of this review* - the new `rescheduleSoon` doc comment cites `reviews-4/REVIEW-3.md` and quotes my 45/240 and 33/240 figures, and the probe file's first line reads "TEMPORARY - independent re-measurement of reviews-4/REVIEW-3.md finding 1". This file was committed as `f3e5aa1` before I had finished correcting its citations, so it also shows as modified; the content on disk is my final version. I touched none of it.
