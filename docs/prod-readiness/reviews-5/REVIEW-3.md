# REVIEW-3 - round 5, stage 2, items 2 and 4 (N4-2 + N4-16), range `c94dbbd..cdb509e`

Reviewed head `cdb509eee5bec5ab68ef3095f42bdaa192bb38c3`, branch `prod-readiness-5/2026-08-15`.
The range contains eight commits: `fedb636` and `bb0c0f9` (R2's record-only tail, declared here per REVIEW-1 finding 6), `fa9b3f4` (item 2's guard), `617e7c6` (test-file split), `13082eb` (item 4's visibility rule), `22f2a72` (user doc), `bc2256c` and `cdb509e` (ledger only).
All mutation and probe work was done in one detached worktree at `cdb509e` under my own scratchpad; every mutated file was restored from a saved pristine copy and byte-compared with `cmp`, the worktree was `git status --porcelain` clean before removal, and `git worktree list` now shows only the main tree.
The main working tree was never modified except to write this file.

verdict: PASS-WITH-FINDINGS

## Summary

**The guard is real, uniform, and correctly bounded, and I could not break it or catch its record in a false number.**
Every measured claim in the ITEM 2 and ITEM 4 sections reproduces by execution on this host: the per-family sweep (all nine detected families 0 scheduled / 0 pending with `ledgerFailures` naming the subscription and `canClaimCoverage` false, healthy control untouched at 4), the pre-guard wrong-day fire dates to the day (my guard-deletion mutant re-produced the stage's whole reconfirmation table, 9-16 and 10-19 and 10-6 included), the corrupt-`lastUsedDate` and corrupt-`pauseEndsOn` shapes, and item 4's own falsification - reverting the view gate to active-only fails the pixel assertion on byte-identical windows of exactly the 34,674 bytes the ledger records, and passes restored.
The five-dimension table is exact: verify.sh exit 0 at 265/127/228 = 620 (twice, from clean clones), lint clean over 230 files, the simulator suite at 133/72/63 with 9 known issues and `** TEST SUCCEEDED **` on three consecutive full runs, the harness at 1/1/5 with the same five citations, and twelve of twelve clean 228-test host runs.
My four-mutant battery confirms the named tests bite: deleting the guard fails 6 tests across both host packages, narrowing the plausibility boundary by one year fails the stage's two boundary tests plus two pre-existing pins, reverting the view gate fails the host matrix and the simulator pixel floor, and adding a status gate to `recordUsage` fails exactly the test the ledger says was built to catch it.
No test was weakened beyond the decided 4 -> 0 expectation change, the split commit moved the new suite without touching a pre-existing line, the `OSLogStore` count stays ten, and every commit is inside the declared R3 range with a one-sentence message.

**What the findings are about is the edges of the record, not the code.**
The user doc's new absolute - a detected-corrupt subscription "is sent nothing at all" - has an undisclosed exception I demonstrated by execution: a wrong-day snooze created before the update survives every silencing pass (the reconcile spares snoozes by design), and "remind me later" on an already-delivered wrong-day notification schedules a new request for a subscription the policy says is silent.
The decision sentence records the user choosing to stop scheduling from a detected-implausible **anchor**; the shipped rule silences on any detected field, which the record describes accurately but never owns as the stage's own extension of the decision.
And the §7.2 zombie report still reads a corrupt `lastUsedDate` raw - a behind-offset day forces a zombie row, an ahead-offset day suppresses one - the exact sibling of the `pauseEndsOn` display residual N5-3 records, recorded nowhere.
All three are P3; nothing here approaches a REJECT.

## What I ran

All measurements at `cdb509e`.
Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five dimensions at the stage-2 head

| dimension | ledger claims | measured here | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0, 265/127/228 = 620 | **exit 0; 265 / 127 / 228 = 620**, two independent runs, each from a clean clone of the committed head | exact |
| `swiftlint --strict` | clean, 230 files | **0 violations, 0 serious in 230 files** | exact |
| simulator suite, full | 133/72/63, 9 known issues, `TEST SUCCEEDED` | **133 / 72 / 63, `with 9 known issues`, `** TEST SUCCEEDED **`** on all three full runs | exact; the 9 = the 7 `EmptyStateTests` issues + the 2 label/activation halves ITEM 4 pre-declared, verified by name in the logs |
| non-Gregorian harness | 1 / 1 / 5, same citations | **1 / 1 / 5** (228-test bundle): `DisplayFormattingTests.swift:49` under Buddhist and Japanese; `:49`, `:59`, `:68`, `:69` and `NotificationReconciliationTests.swift:170` under `ar_SA` | exact |
| flake, twelve full host runs | 12 of 12 (228 tests per run) | **12 of 12 passed**, 228 tests each, 7.4 s - 13.4 s | clean |

Per-commit build sweep: `fa9b3f4` and `617e7c6` (the intermediate code commits) both build `--build-tests` for OttoDomain and OttoUI; the head is covered by verify.sh from a clean clone.

### The ledger's sweep, re-derived rather than accepted

My own probe suite through the real scheduler (`SchedulerFixture`, the shipped fixtures), one corrupt anchor per detected family with a healthy control seeded beside it in the same pass:

- **All nine families**: `ledgerFailures == [corrupt.id]`, `canClaimCoverage == false`, zero pending requests carrying the corrupt subscription's identifier, and the healthy control at exactly 4 pending with `scheduledCount == 4`.
- **Corrupt `lastUsedDate` beside a healthy anchor** (Buddhist-written 2569 and Indian-written 1948): 0 scheduled, pending empty, failure named - the whole-subscription silence the ledger states.
- **Corrupt `pauseEndsOn` on a paused subscription** (1948-09-01): 0 scheduled, pending empty, failure named - the planner half of N5-3's phantom un-pause is genuinely stopped.

The pre-guard behaviour was re-derived by deleting the guard (M1 below) and reading the failure dumps: every behind-offset family plans exactly 4 rungs, and the wrong-day fire dates match the stage-start table to the day - japanese 9-16, chinese 9-19, islamic 9-5, persian 10-19, minguo 10-6, indian 9-16 - while Buddhist and Hebrew plan 0 with no issue recorded, the Indian-written `lastUsedDate` plans 4 with the 9-23 wrong-day check-in, the Buddhist-written one plans 3, and the corrupt-resume pause plans the 9-3 / 10-3 / 11-3 / 11-4 set that is identical to the healthy control's.
So the seven-family understatement correction, the two newly-named shapes, and the un-pause measurement are all real, not transcribed.

### Falsifications - mine; the stage shipped no battery of its own and claimed none

Each mutation was applied by a script that asserted the target text's occurrence count was 1, in the worktree, and restored from a pristine copy verified with `cmp`.

| # | what I broke | failing tests | result |
|---|---|---|---|
| M1 | the planner guard line deleted from `ReminderSchedule.swift` | OttoDomain: all 3 corruption tests in `ImplausibleDayPlanningTests`, 10 issues; OttoUI host: the behind-offset pending test, the Indian `scheduledCount == 0` test, and `repairRestoresScheduling`, 4 issues | **killed at both levels** |
| M2 | `<=` -> `<` on the behind check in `isPlausibleStoredDay` (70 years back becomes implausible) | "the plausibility boundary itself still plans", "the repair rule applies the plausibility rule, not a private threshold", plus two pre-existing `StoredDayPlausibilityTests` pins | **killed by exactly the named boundary tests** |
| M3 | `UsageSectionView.isShown` reverted to active-only | host: `corruptShowsRepair` fails for all three statuses; simulator: the pixel assertion fails on **byte-identical 34,674-byte windows** - the ledger's falsification reproduces to the byte - and the restored file passes | **killed; the recorded falsification is real** |
| M4 | `guard ... effectiveStatus == .active` added to `recordUsage` | `recordUsage writes today over a corrupt day on paused, trial and cancelled`, 3 issues | **killed by the test the ledger says pins this** |

Under M3 the simulator's `repairWrites` test still passes (its activation half is a known-issue skip with no accessibility client), so on this rig the revert is caught by the pixel floor and the host matrix, not by the activation test - which is what ITEM 4's cost paragraph says to expect.

### The seam, checked by enumeration

`reminderSchedule` has exactly one production caller (`NotificationScheduler.reschedule`, line 121), materialization is skipped by the ledger loop on the same predicate, and no flow service or store writes notification requests directly.
The one path that reaches the notification center outside the plan is `NotificationActionHandler.snooze`'s direct `client.add` - finding 1.

## Findings

### 1 - P3. A pre-update wrong-day snooze survives the silencing pass, and a delivered wrong-day notification's snooze still schedules - "sent nothing at all" has an undisclosed exception

**Evidence, both halves executed.**
Probe: seed a detected-corrupt subscription (Islamic-written anchor 1448), pre-add a snooze request in the snooze identifier namespace (what a user on the pre-guard build created from one of the four wrong-day reminders), run the real pass.
Result: `scheduledCount == 0`, `ledgerFailures` names the subscription, and the pending set afterwards is **exactly the snooze** - `NotificationScheduler+Reconcile.swift:36` filters snoozes out of the stale set by design, so no number of silencing passes ever removes it.
Second probe: `handle(actionIdentifier: remindLater)` on an already-delivered wrong-day identifier for the same corrupt subscription schedules a **new** pending request (fires next day at the preferred hour) - `snooze` checks nothing about plausibility and computes its deadline cap from the corrupt anchor via `nextBillingDate`.

`docs/next-wave.md` now states "A subscription with any detected-corrupt day is sent nothing at all - on every detected calendar" and "Silence plus the coverage-gap card IS the corruption signal."
Both sentences are true of the scheduling pass and false in the upgrade window where the corruption story actually plays out: the user who snoozed a wrong-day reminder before updating gets that reminder anyway, on a wrong day, from a subscription the doc says is silent.
The ledger's "0 scheduled / 0 pending for every detected family" is accurate for the pass and was measured on a clean notification center; nothing in the range's record names the snooze carve-out.

Not a code defect: sparing snoozes is Wave 10's deliberate design, and cancelling user-created state from a corruption guard would be its own decision.
The gap is disclosure - one sentence in the doc's corruption section and one in ITEM 2's record would close it, or the round decides the pass should also drop snoozes for ledger-failed subscriptions, which is a behaviour change beyond this stage's grant.

### 2 - P3. The record attributes the any-field silencing to a decision it states as anchor-only

**Evidence.**
`PROD-READINESS-5.md` ITEM 2: "The decision this item was waiting on has been taken - by the user, not by this run: a detected-implausible **anchor** stops scheduling entirely (option 2 of the five presented)".
The shipped guard is `subscription.implausibleStoredDays(asOf: today).isEmpty` - anchor, trial start, trial conversion, `pauseEndsOn` and `lastUsedDate` - and the behaviour is described accurately ("any detected-implausible stored day means the subscription plans NOTHING") and tested per field.
But no sentence records that the per-field extension is the stage's own inference rather than what the decision sentence says was decided; the nearest thing is a test comment ("the subscription-level silence is the decision, because a partially-wrong plan reads as a healthy one"), which asserts the very attribution in question.
N4-2's work-list row and reconfirmation are about corrupt **calendars** writing wrong anchors; the corrupt-`lastUsedDate` and corrupt-`pauseEndsOn` shapes were, in the ledger's own words, "shapes ... no ledger entry had named".

The extension is almost certainly right - the ledger loop has treated any implausible stored day as a per-subscription failure since round 3, so planner and ledger now agree, and a partially-wrong plan indistinguishable from a healthy one is the exact defect class this round exists to kill - and I am not re-litigating it.
The defect is that this ledger's history is precisely of small unattributed steps compounding (`reviews-5/REVIEW-2.md` finding 3, `reviews-4/REVIEW-3.md` finding 2), and a future reader of ITEM 2 will quote "the user decided" for a rule wider than the decision sentence states.

**What would make it right.** One sentence in ITEM 2 owning the extension: the user's option 2 named the anchor; this stage applied it to every detected field because the ledger half already did and a partial plan reads healthy - or, if the user's actual decision did cover every field, the decision sentence should say so.

### 3 - P3. The §7.2 zombie report reads a corrupt `lastUsedDate` raw, and no entry records this surface

**Evidence, executed.**
`zombieReport(subscriptions:asOf:)` (`ZombieReport.swift:58`) takes `subscription.lastUsedDate ?? billingAnchor` with no plausibility check.
Probe at the head: a behind-offset corrupt day (Indian-written 1948) puts the subscription **in** the report - a zombie row claiming ~78 years unused - and an ahead-offset one (Buddhist-written 2569) keeps a genuinely unused subscription **out** of it.
Both wrong, in opposite directions, until the item-4 button is tapped.

This is the `lastUsedDate` sibling of exactly what N5-3 records for `pauseEndsOn` ("list rows, detail screens and the §7.2 report still derive status from the corrupt date"), and stage 2 is the stage that put `lastUsedDate` corruption on the record - but N5-3 is scoped to the §5.2a status derivation, ITEM 2's residuals name only Ethiopic and N5-3, and ITEM 4 records the repair without noting the report stays skewed until it is used.
Pre-existing, not a regression of this range, and mitigated by item 4 making the repair reachable; recorded so the disclosure ledger is complete rather than field-by-field lucky.

**What would make it right.** Extend N5-3's sentence to name the report's `lastUsedDate` reference alongside the status derivation, or a one-line sibling entry.

## The flagged copy question, answered as asked

ITEM 4 flags rather than decides whether "I used this today" deserves repair-specific wording on a non-active subscription.
Position: the deferral is correct.
The button's action is exactly right on every status (the field records a day of use and today is the only day the user can truthfully assert), the oddity is confined to the cancelled case, and re-wording is new user-facing copy that this stage had no exception for - it belongs with item 9's copy work, which is already the open item about corruption-adjacent copy.
Not a finding.

## Explicit checks

- **Fabricated or unreproducible numbers.** None found. The sweep, the wrong-day dates, the 34,674-byte falsification, all five dimensions, the +4/+8 host and +3/+7 simulator test arithmetic, and the "9 known issues = 7 + the 2 pre-declared" composition all reproduce exactly. The stage's stochastic surface is small (three sim runs, twelve host runs) and matched on every run I made.
- **Tests weakened.** One expectation changed in the range: `ImplausibleStoredDayTests` `scheduledCount == 4` -> `== 0`, which is the decided policy itself, stated in an eight-line comment at the site. `fa9b3f4` deletes zero pre-existing test lines; `617e7c6` moves the new 81-line suite into its own file plus three import lines and touches nothing else; no other test file in the range loses an assertion.
- **The guard's boundary, both directions.** Narrow-by-one is killed by the stage's own boundary tests (M2). Widen-by-one I did not execute as a mutant; the constant is pinned exactly by the pre-existing `#expect(CalendarDay.plausibleStoredDayYearsBehind == 70)` and the 1955/1956 pair at `StoredDayPlausibilityTests.swift:203-211`, which I read rather than mutated. Ethiopic-shaped days (2018 anchor) plan through the guard, asserted by the shipped boundary test and reconfirmed under M2.
- **One corrupt subscription beside healthy ones.** The shipped sibling test is unchanged and green in every run; my sweep seeds a healthy control beside the corrupt one in all nine families and it schedules 4 every time.
- **The gap card.** `TodaySectionPlan.plan` appends `.coverageGap` on `canClaimCoverage == false`; `canClaimCoverage` is `ledgerFailures.isEmpty`; the range touches neither file, so "the card's trigger set is unchanged" is true by diff, and my sweep confirms every detected family drives the flag false.
- **The repair arc.** `repairRestoresScheduling` executes silence -> repair -> reschedule at the scheduler level and fails under M1, so the doc's "reminders resume on the first scheduling pass" sentence is executed, not asserted from structure.
- **`OSLogStore`.** No reader added; the range's only two mentions are ledger prose; the count stays ten.
- **Range hygiene.** All eight commits are inside the declared R3 range, R3's start is R2's head (`c94dbbd`), every commit message is one short sentence with no trailer, and the two record-only R2-tail commits carry no code (verified by `--name-only`).
- **Scope.** The range touches one domain file, one view file, four test files, the user doc and the two record files; no `Package.swift`, no lint config, no workflow, no schema, no new dependency, no UI-test target.
- **Citations.** The ":163 now at :164" claim is correct at `c94dbbd`; the `SKIPPED reason=implausibleStoredDays` guard in `SchedulingLogTests` is untouched at line 169; the sweep table's `bb0c0f9` provenance is consistent with what the guard-deletion mutant reproduces at the head.
- **Simulator dimension composition.** The two new known issues are exactly `UsageRepairReachabilityTests.swift:290` and `:322` (the label and activation halves), by name, in all three runs.

## Attempted refutations that did not become findings

- **Reaching the scheduler with an implausible day through another path.** Enumerated every production caller of the planner (one), the materializer (skipped on the same predicate), and the notification-center writers (the pass and the snooze); only the snooze survives, and it is finding 1. Catch-up delivery cannot carry a corrupt-day rung because the catch-up set is a subset of the plan, which is empty for a detected subscription - confirmed by the pending-set probe, which shows zero requests of any trigger type.
- **Making the guard over-reach.** A day exactly 70 years back plans, an Ethiopic-written day plans, and a plausible `lastUsedDate` off the active state stays hidden - all executed, all green pristine, all red under the right mutant.
- **Catching the sim suite flaking on the new known-issue tests.** Three consecutive full runs with byte-identical counts and the same two known-issue sites; the rendering suite alone also passes scoped, pristine, and fails only under M3.
- **Catching the split hiding a change.** The 84-line new file is the 81 deleted lines plus three imports; `ReminderScheduleTests.swift` is net-unchanged across `fa9b3f4..617e7c6`.
- **The N5-3 planner half.** A behind-offset `pauseEndsOn` derives `.active` (the pre-guard M1 dump shows renewal rungs and a check-in, an active-shaped plan) and the guard stops all of it at the scheduler level - N5-3's claim that only display surfaces remain is correct as far as planning goes; finding 3 is about the one display surface its sentence does not name.

## What I could not check, and why

- **The decision conversation itself.** "Option 2 of the five presented" and its anchor wording are taken from the ledger; whether the user's actual words covered every field is exactly what finding 2 asks the record to state.
- **The R2-head column of the five-dimension table.** `reviews-5/REVIEW-2.md` verified those figures at `c94dbbd`; I did not re-run them there.
- **The label/activation halves of the rendering tests.** No accessibility client attaches on this rig (the standing `EmptyStateTests` condition), so they are known-issue on every run here and assert only where a client exists.
- **Release configuration, a physical device, a real non-Gregorian device.** Debug, simulator, host harness only, as in every prior round.
- **Whether pre-guard planned (non-snooze) wrong-day requests are removed on the first post-update pass.** Structurally they are (the reconcile's stale set is everything planned that the empty plan no longer wants, and its removal path is round-old tested); I executed the pass only against an empty center and a pre-seeded snooze, not against pre-seeded planned rungs.
