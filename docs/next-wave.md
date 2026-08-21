Next wave: **6B - CloudKit activation**, specified in `docs/Subscription-Tracker-Spec.md` §8 (v2.6), gated on the manual checks in `docs/cloudkit-readiness.md`.
Wave 10 (Notification Delivery & Check-Date Fixes, from the Aug 2026 device run) landed in between; 6B remains the next planned wave.
Carry-over candidates for a later wave: simulator-hosted `NotificationCoordinator` tests (see `docs/implementation-notes/wave-10.md`, "Deliberately not done").

---

# If a device was set to a non-Gregorian calendar before this build

**The repair is manual, it works, and nothing in the app says so.** This is the only place it is written down for a user rather than for a reviewer.

Otto stores billing dates as plain year/month/day numbers. A build before F1 resolved those numbers through the *device's* calendar, so a phone set to Buddhist, Japanese, Islamic, Persian, Coptic, Minguo, Chinese, Hebrew or Indian wrote an era-numbered year into billing data - 2569 rather than 2026 on a Buddhist device, 1948 rather than 2026 on an Indian one. F1 stopped new writes from going wrong. **It repaired nothing already stored, and no automatic repair is possible**: which calendar wrote a given day was never recorded, and guessing it would rewrite dates that are correct. `PROD-READINESS-3.md` ITEM 1 has the full reasoning.

**How to tell.** The subscription list and detail screens show the wrong dates in plain sight - "Aug 6, 2569". Today shows the coverage-gap card, which since round 5 says what actually happened ("N subscriptions with unusable dates" - Otto stopped their reminders on purpose, and fixing the dates is what brings them back), and the unified log carries one line per affected subscription naming exactly which days are wrong:

```
log show --predicate 'subsystem == "com.arthurzhang.otto" AND category == "scheduling"' --last 1h
[scheduling] ledger <uuid> SKIPPED reason=implausibleStoredDays today=2026-08-11 days=[2569-08-06 2569-08-20]
```

**How to fix it, field by field** - because not every date the log names has a picker, and an earlier version of this section said to re-pick all of them, which is not possible.

| the log names | how to repair it |
|---|---|
| the next charge date (`cycleStartDay`) | Edit the subscription and re-pick **Next charge on** (or **Started on**). Since F1 the picker writes Gregorian whatever the device calendar is. |
| the trial start / conversion date | Edit the subscription and re-pick **Trial started**. The conversion date is derived from it and repairs with it. |
| a pause resume date (`pauseEndsOn`) | **There is no picker for this on an already-paused subscription.** Resume the subscription and pause it again, setting **Billing resumes** in the pause flow. |
| the last recorded use (`lastUsedDate`) | Open the subscription and tap **I used this today**, in the Usage section of its detail screen. There is no picker; that button is the only control that writes this field, and it writes *today*, which is correct. **Two things to know.** First, do not wait for a notification to prompt you: a subscription with any detected-corrupt day is sent nothing at all (see below), so the reminder that would prompt the repair is exactly what the corruption suppresses. Second, when this field is corrupt the Usage section appears **whatever the subscription's status** - paused, trial and cancelled included - so the repair is always reachable; on a healthy subscription the section stays active-only, as before. |

Nothing is deleted and no charge history is lost; only the stored dates change. A subscription is repaired - and starts scheduling again on the next pass - once **every** day the log line names is fixed, so a paused or never-used subscription may need the second and third rows above as well as the first.

**Every repair above is something you do in the app, on purpose. Do not wait to be prompted.**

**A subscription with any detected-corrupt day is sent nothing at all - on every detected calendar.**
Buddhist, Hebrew, Japanese, Minguo, Islamic, Persian, Coptic, Chinese and Indian/Saka corruption all behave the same way now: no reminders are scheduled from any of the subscription's dates, Today shows the coverage-gap card, and the log line above names the exact days to fix.
It used to depend on which calendar wrote the year - the behind-offset calendars projected the corrupt dates forward and sent four reminders on days that were not the billing dates - and that ended in round 5: a wrong-day reminder read as a healthy subscription, so detected corruption now stays silent on purpose.
**Silence plus the coverage-gap card IS the corruption signal.**
Reminders resume on the first scheduling pass after every day the log line names is fixed.

**One carve-out: snoozes.**
Otto never cancels a snooze you created, so a reminder snoozed before this build updates still fires once, and tapping "Remind me later" on a wrong-day reminder that was already delivered schedules that one snooze - each from a subscription this section otherwise calls silent.
Nothing follows them: after a snooze fires, the silence holds until the dates are repaired.

**One calendar leaves no signal at all.** Ethiopic writes 7-8 years behind the Gregorian year and is indistinguishable from an ordinary subscription held since 2018, so Otto cannot detect it: there is no card, no log line, and reminders still arrive on the wrong days - Ethiopic is the one calendar the round-5 silencing cannot reach. The dates on the subscription list are still visibly wrong, and re-picking them is still the fix. Indian/Saka was in the same position until round 4 made the detection window asymmetric.

---

Gate 1 (2026-08-08) landed the GitHub remote and the first CI run; see `DECISIONS.md`, "Gate 1".
Standing consequence for every later wave: **CI, not `verify.sh`, is now the gate.**
`verify.sh` clones the committed code into the same locale on the same hardware, so it cannot see a host-environment dependency - which is exactly what CI's first run found twice.
Gate 2 (`BGAppRefreshTask`) is **met** as of 2026-08-08: the handler was observed executing on device in both Debug and Release after a one-line isolation fix, having crashed on every attempt before it.
Fixing the crash exposed a second defect it had been hiding - expiration completed the task while the pass ran on and completed it again - and that is fixed too (§9a), with both a completion latch and real cancellation checkpoints.
Carry into 6B: **a subsystem reporting that it accepted your work is evidence about the subsystem, never about your code.** `dasd` scheduled the dead background task for months; CloudKit's acknowledgements will be exactly as reassuring.

---

# ✅ Gate 3 (delete-and-reinstall) is MET - second run, 2026-08-16

The last of the three manual gates before 6B.
The first run (2026-08-08) destroyed and restored the container but was voided by a wrong-file import; the second run completed the resume procedure and every criterion passed.
Full evidence in the `docs/manual-verification.md` run log (2026-08-16 row).

| Criterion | State |
|---|---|
| Container genuinely destroyed by uninstall | ✅ 2026-08-08: `ContainerLookupErrorDomain error -1`, zero files retrieved |
| True first-run state after reinstall | ✅ 2026-08-08: `permission=notDetermined scheduled=0`, no ledger lines, 0 rows |
| Three subscriptions, correct amounts | ✅ $A/mo, $B/yr, $C/yr |
| Correct next-charge anchors | ✅ `<anchor-A>` (→ one month on), `<date-C>`, `<date-B>` |
| Monthly burn reconciles to $D | ✅ computed D from the restored container |
| Payment method returns, 3 subs billed to it | ✅ 1 live payment method, 3 live subscriptions reference it |
| Watermarks reconstructed from the ledger | ✅ 2026-08-16, verified before permission re-grant: Subscription A **<date-A>** (ledger), Subscription C **<date-C>** (anchor), Subscription B **<date-B>** (anchor) - never today |
| Notifications re-scheduled | ✅ 2026-08-16: `permission=authorized scheduled=7 coveredThrough=2026-11-14 ledgerFailures=0`; all 7 identifiers (each carrying its trigger date) captured via reconcile read-back and content-compare - see the run log for why LLDB cannot dump the pending set on this host |

The verified export (`<backup-dir>/Otto-Export-VERIFIED-pre-gate3-2026-08-08T2213Z.json`, sha256 `b578cde5…`, 9,264 bytes) and the two raw container backups in `<backup-dir>/otto-container-backup-*` remain on disk; read copies, never the originals (`sqlite3` truncates a WAL on open).
The Replace path was chosen by hand because procedure 4's step 6 in `docs/manual-verification.md` says to, and that step's stated reason - the empty-database `.merge` default skips watermark reconstruction (§9a) - was already false on the day: the defect was fixed at `b15b0a6` (2026-08-10) and refined at `d00c086` (2026-08-11), while the warning text has stood unchanged since it was written on 2026-08-08. Which build was on the phone is unrecorded, and answering Replace by hand reconstructs watermarks on a fixed and an unfixed build alike, so the run's own evidence cannot settle it either way - see defect 1 below.
The run's P3 observation - a settings `stateChange` ran the full scheduling pass twice concurrently (duplicated pass/ledger/reconcile lines), idempotent but doubled - was **fixed 2026-08-20** (`0787150`): the picker's hour-then-minute writes each fired the reschedule hook, `didSet` firing on same-value assignments included; one picked time now notifies at most once. See `DECISIONS.md`, "One picked time, one pass".

## The honest boundary to state when reporting it

This gate proves a **manual** export/restore floor exists. It does not prove any automatic protection, and §8's first CloudKit prerequisite - an automatic pre-enable export snapshot - is a different thing this does not satisfy.

Also state plainly: **the uninstall clears the notification permission, so reminders do NOT come back with the data.** They return only after the user re-grants and a scheduling pass runs. "My data came back" and "my reminders came back" are different promises, and only the first one is what this gate establishes.

## Two ⛔ defects found during Gate 3 that 6B must decide on

Both are recorded in §9a with full analysis.

1. **An empty-database import silently skips watermark reconstruction** (above). **Fixed 2026-08-10** (`b15b0a6`), **refined 2026-08-11** (`d00c086`): the better fix was the one taken - the watermark policy is decoupled from the merge strategy, so an import into a database with **no live subscriptions** reconstructs from the imported ledger whatever the strategy says. Keyed on live subscriptions rather than emptiness because an all-tombstoned database is not empty - a complete snapshot carries tombstones by design - but has no watermarks either.
   **6B is not blocked by this.**
2. **Merge rules order on wall-clock timestamps, and the device clock is not monotonic** - found in real exported data, where two records carry a `deletedAt` PRECEDING their `createdAt`, written under the advanced clock of manual procedure 1. Full analysis and three fix options in `docs/sync-safety.md`.
   **DECIDED and implemented 2026-08-16** (`DECISIONS.md`, "Sync safety - the monotonicity decision"): options 2+3 combined - write-time clamps at every stamping site, deterministic order-repair of `updatedAt`/`deletedAt` before any import comparison, and future stamps clamped to the import instant so they cannot stay sticky under last-writer-wins.
   Option 1 (logical clocks) was rejected: CloudKit's own field-level conflict resolution cannot be fed one, so it would be the largest change with partial coverage; held in reserve if two-device damage appears.
   Residual, accepted and documented: honest cross-device clock skew still orders last-writer-wins wrongly - §8 prerequisite 4's documented residual, mitigated by the snapshot/kill-switch/restore floor.
   **6B is no longer blocked by this.**
