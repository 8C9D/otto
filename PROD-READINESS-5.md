# PROD-READINESS-5 - Otto, round 5

Bounded remediation of a frozen list, opened 2026-08-15, branch `prod-readiness-5/2026-08-15`, from commit `1b352f4` on `main`.

Baseline artifact: `reviews-5/BASELINE-5.md`.
Review trail: `reviews-5/`.

This is the first round to start from `main`.
The round-1 through round-4 stack was merged at `1b352f4` (parents `cd9778c` and `9e73378`); the merge is local and unpushed at opening.

**This is not a discovery sweep.**
Every item below was found, evidenced and adversarially reviewed in the four runs that produced `PROD-READINESS.md` through `PROD-READINESS-4.md` and their review trails.
This round's job is to close the P2 list that round 4 carried, honestly, and to say plainly what it cannot close.
No prior record is edited by this run.

Rounds 1 through 4's terminal states and scope constraints still bind.

---

## Baseline

`scripts/verify.sh` at `1b352f4`, from a clean clone: **exit 0 - OttoDomain 261, OttoPersistence 127, OttoUI 209, total 597**, `swiftlint --strict` clean over 225 files.
Simulator suite from `Packages/OttoUI/`: exit 0, `** TEST SUCCEEDED **`, **119 / 72 / 53, 7 known issues**.
Non-Gregorian harness: **1 / 1 / 5** under `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`, the same five citations as every prior baseline.
Flake batch: **12 of 12 clean full `swift test --package-path Packages/OttoUI` runs.**

All five round-4 terminal figures reproduce exactly.
Full output, provenance and the environment table are in `reviews-5/BASELINE-5.md`.

**The `OSLogStore` reader count at this HEAD is ten** - seven in OttoUI, three in OttoPersistence, enumerated by call site in the baseline.
The standing rule is applied to the real number: **do not add an eleventh**.
The CI-runner delivery risk stays in CANNOT ASSESS.

---

## THE WORK LIST - frozen at opening

Every P2 carried open in `PROD-READINESS-4.md`'s NEXT ROUND section, and nothing else.
All P3s stay in NEXT ROUND.
Item 1 leads because N4-7 is the highest-value code fix on the carried list, and N4-3's own entry routes its fix through N4-7's.

| # | id | what | terminal state |
|---|---|---|---|
| 1 | **N4-7 + N4-3** | The reschedule coalescing gate is in the wrong class, and the background pass is outside it | open |
| 2 | **N4-2** | Negative-offset corrupt calendars still schedule reminders on wrong days, and no round has decided whether they should | open |
| 3 | **N2-4** (reopened) | The reconcile failure list still truncates at the per-entry budget; round 2's closure was false | open |
| 4 | **N4-16** | `lastUsedDate` has no repair on a paused, trial or cancelled subscription | open |
| 5 | **N4-1** | The export button's action is verified by nothing | open |
| 6 | **N4-10** | The §6.2 reconcile diff line has no executable guard | open |
| 7 | **N4-11** | A sibling's canary masks a deleted canary wherever tests share a log window | open |
| 8 | **N2-1** | Five locale-sensitive test citations fail under non-Gregorian hosts | open |
| 9 | **N3-5** | The gap card's copy is false for the implausible-days case, now including Indian/Saka | open |
| 10 | **N3-6b** | `NotificationCoordinator.start()` and the delegate have no test | open |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded).
There are no others.

### Item 1 - N4-7 + N4-3: the reschedule gate is in the wrong class

Three callers share one `NotificationScheduler`: the coordinator's `rescheduleSoon` (gated by round 4's item 4), `handleBackgroundRefresh` (not gated), and `NotificationStatusStore.reschedule()` (not gated, and the most frequent in ordinary use).
Measured overlap with a coordinator pass: **45 of 240** iterations for the background path and **33 of 240** for the store path (`reviews-4/REVIEW-3.md`), re-measured at **74 of 180** for the background path with a spy modelling the real pass's suspension points.
`handleBackgroundRefresh` owns the completion latch and the expiration race and builds its own `Task`, so a background wake-up landing during a foreground pass runs a second, interleaved pass - F10 itself, still live on two of three entry points.
Closing this means putting the gate at the `ReminderScheduling` seam all three callers share, and it needs its own measurement of what `expirationHandler` then cancels.

### Item 2 - N4-2: wrong-day reminders from negative-offset corrupt calendars

Round 3's "closed for 11 of 13" was measured on Buddhist, the one calendar where the stored year is ahead and nothing is scheduled.
For every negative-offset calendar the planner still produces rungs from the corrupt anchor: Japanese, Minguo, Islamic and Persian each schedule **4 reminders on the wrong days** (measured at round 3's HEAD), and round 4 added Indian to that set.
The state closed for those calendars is "wrong reminders, disclosed", not "no reminders".
Whether to stop scheduling from an implausible anchor is a decision no round has taken; this round must take it or defer it explicitly.

### Item 3 - N2-4, reopened: the failure list still truncates

Round 2 recorded this fixed by giving the failure list its own log entry.
`reviews-4/REVIEW-AA92CA7.md` finding 1 measured the closure false: the entry sits under the same ~1024-byte per-entry budget, buying only the ~200 bytes of prefix.
The list still truncates from six subscriptions upward and names **16 of 64** failed rungs at the device ceiling, measured at `aa92ca7` and at round 4's tip.
The false closure propagated into `PROD-READINESS-3.md`; the propagation is recorded in round 4 and is not re-litigated here.

### Item 4 - N4-16: no `lastUsedDate` repair off the active state

The only control that writes `lastUsedDate`, "I used this today", is inside `if subscription.effectiveStatus(asOf:) == .active` (`PauseFlowView.swift:163` at round 4's tip).
A corrupt `lastUsedDate` on a paused, trial or cancelled subscription therefore cannot be repaired without first changing the subscription's status, which is a data change the user did not want to make.
`docs/next-wave.md` says so; the app offers nothing.

### Item 5 - N4-1: the export button's action is verified by nothing

Deleting the sole call from the Settings export button's tap to `AppModel.requestExport(_:)` leaves the whole simulator suite green.
Round 4's remediation shrank the untested surface to one closure with no logic in it and moved the state machine onto the model, where eight tests reach it - but the closure itself is unreachable by any test this project can run.
Closing it needs a UI-test target, which round 4 was not permitted to add; this round must either add that target deliberately or defer with the dependency named.

### Item 6 - N4-10: the reconcile diff line has no executable guard

Deleting the §6.2 reconcile diff log statement is green at `aa92ca7` (196/196) and still green at round 4's tip (209/209); the same deletion at `aa92ca7`'s parent fails.
The file split in `aa92ca7` is what removed the guard, and no reviewer saw that commit's diff for three rounds (`reviews-4/REVIEW-AA92CA7.md` finding 2).

### Item 7 - N4-11: a sibling's canary masks a deleted canary

`requireDelivered` answers "did the subsystem deliver for this process", which a sibling test's canary answers correctly - so the guard is sound and the **falsification** of it is what breaks wherever tests share a log window.
Found twice independently in round 4, in commits three rounds apart.
Every canary falsification in this tree needs `--filter` or a suppressed subsystem, and none of the canary sites says so.
The general form is recorded in round 4: this tree has no way to prove a log line came from a particular test, only to make collision unlikely.

### Item 8 - N2-1: the five locale-sensitive citations

`DisplayFormattingTests.swift:49`, `:59`, `:68`, `:69` and `NotificationReconciliationTests.swift:170` fail under the harness locales - `:49` on any non-Gregorian host, `:170` where the month disagrees, and the three numbering-system cases under `ar_SA` alone.
Unmoved at every baseline since round 2, including this one.

### Item 9 - N3-5: the gap card's copy is false for the implausible-days case

The card's copy does not survive the implausible-days case, and round 4's Indian/Saka detection widened the set of subscriptions the false copy covers.
Re-wording it is new user-facing copy; round 4's user-facing exception was granted for the export item only, so the item stayed open.

### Item 10 - N3-6b: `start()` and the delegate have no test

`BGTaskScheduler.register`, `UNUserNotificationCenter.current()`, `UNNotification` and `UNNotificationResponse` still have no test-safe construction, so `NotificationCoordinator.start()` and the delegate methods remain untested (round 4 added four simulator-hosted coordinator tests around them; the entry points themselves are still unreached).

---

## STANDING RULES - carried forward, binding on every stage of this round

- **Review ranges**: every review range's START is the previous range's HEAD, stated by sha in the review; no commit may fall outside every range (the `aa92ca7` lesson, N3-4).
- **`OSLogStore` readers**: ten in the tree at this baseline; do not add an eleventh.
  Every canary falsification must state its `--filter` or suppression (item 7 is the fix for this rule's blind spot).
- **Flake discipline**: any claim about a test's stability requires twelve full unmutated `swift test --package-path Packages/OttoUI` runs; a single run - green or red - proves nothing about an intermittent event.
- **Terminal vocabulary**: RESOLVED with artifact evidence, DEFERRED with reason, REJECTED TWICE with the revert and the objection recorded; two REJECT cycles on a range is the cap.
- **Measurement before edit**: every item is reconfirmed by executing the defect before it is touched.
- **No prior record is edited**; corrections to this round's own record name what they correct.
- **Scope**: nothing outside the ten items above may be changed except as a reviewed remediation of this round's own work; all P3s and the non-P2 residuals (R0-7's repair and the Ethiopic residual, Round 0 §4's two items, N4-18, and the rest of round 4's NEXT ROUND) stay in NEXT ROUND.

## NEXT ROUND

Opens empty.
Round 4's NEXT ROUND section remains the ledger of record for everything this round's work list does not name.
