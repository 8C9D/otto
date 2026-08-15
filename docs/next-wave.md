Next wave: **6B - CloudKit activation**, specified in `docs/Subscription-Tracker-Spec.md` §8 (v2.6), gated on the manual checks in `docs/cloudkit-readiness.md`.
Wave 10 (Notification Delivery & Check-Date Fixes, from the Aug 2026 device run) landed in between; 6B remains the next planned wave.
Carry-over candidates for a later wave: simulator-hosted `NotificationCoordinator` tests (see `docs/implementation-notes/wave-10.md`, "Deliberately not done").

---

# If a device was set to a non-Gregorian calendar before this build

**The repair is manual, it works, and nothing in the app says so.** This is the only place it is written down for a user rather than for a reviewer.

Otto stores billing dates as plain year/month/day numbers. A build before F1 resolved those numbers through the *device's* calendar, so a phone set to Buddhist, Japanese, Islamic, Persian, Coptic, Minguo, Chinese, Hebrew or Indian wrote an era-numbered year into billing data - 2569 rather than 2026 on a Buddhist device, 1948 rather than 2026 on an Indian one. F1 stopped new writes from going wrong. **It repaired nothing already stored, and no automatic repair is possible**: which calendar wrote a given day was never recorded, and guessing it would rewrite dates that are correct. `PROD-READINESS-3.md` ITEM 1 has the full reasoning.

**How to tell.** The subscription list and detail screens show the wrong dates in plain sight - "Aug 6, 2569". Today shows the coverage-gap card ("N subscriptions couldn't be updated"), and the unified log carries one line per affected subscription naming exactly which days are wrong:

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

# ⛔ RESUME HERE: Gate 3 (delete-and-reinstall) is PAUSED, PART-MET

Written 2026-08-09 for someone with **no context from that session**. Gate 3 is the last of the three manual gates before 6B, and it is the one that establishes there is a floor under CloudKit before CloudKit exists. The full procedure is `docs/manual-verification.md` §4 - **read it before doing anything**, especially its two warnings.

## Where it stands

The container was destroyed and restored once, on 2026-08-08. **The data half passed. Two criteria are unmet, and the run used the wrong file, so it does not count.**

| Criterion | State |
|---|---|
| Container genuinely destroyed by uninstall | ✅ proved by `ContainerLookupErrorDomain error -1`, zero files retrieved |
| True first-run state after reinstall | ✅ `permission=notDetermined scheduled=0`, no ledger lines, 0 rows in the container |
| Three subscriptions, correct amounts | ✅ $A/mo, $B/yr, $C/yr |
| Correct next-charge anchors | ✅ `<anchor-A>` (→ one month on), `<date-C>`, `<date-B>` |
| Monthly burn reconciles to $D | ✅ computed D from the restored container |
| Payment method returns, 3 subs billed to it | ✅ Credit card ••XXXX Bank, default, 3 live subscriptions reference it |
| **Watermarks reconstructed from the ledger** | ❌ **UNMET - the table was completely empty** |
| **Notifications re-scheduled** | ❌ **UNMET - permission was never re-granted, so nothing was scheduled** |

**Why the run does not count.** The file imported on the phone was NOT the file that had been verified. The verified export was AirDropped to the *Mac*, so it was never in the *phone's* picker; the phone imported an older 09:48 export already sitting in its Files app (4 subscriptions / 7 events - matches that older file exactly). The code was cleared by reproduction, not by argument: decoding the verified file and restoring it through the real `OttoStore` into a real empty store preserves all 5 subscriptions / 12 events / 1 episode, missing nothing.

**Why the watermark table was empty - this is a real ⛔ defect, not operator error.** An import into an EMPTY database runs `.merge` without asking (`SettingsView.swift:293`), and `.merge` maps to `watermarks: .keep`, so nothing is reconstructed. A nil watermark makes `materializeEvents` start from **today** and skip the window back to the last real charge. The empty database IS the recovery case, so **the default path is the wrong one.** Recorded in §9a and `DECISIONS.md`; NOT fixed. Until it is fixed, the gate must be run by choosing Replace by hand.

## Files you need (all still on disk)

**The verified export - use THIS file, no other:**

```
path    <backup-dir>/Otto-Export-VERIFIED-pre-gate3-2026-08-08T2213Z.json
sha256  b578cde53bd4f8f20fbe8378c641ce303f41e05b4c90205bbb00e989a9926b46
size    9264 bytes
```

Contents, already verified: `formatVersion` 4, `exportedAt` 2026-08-09T02:13:57.753Z, 5 subscriptions (3 live: Subscription A, Subscription B, Subscription C; 2 tombstoned: "Gate Test", "Test"), 12 billing events (3 live), 1 payment method, 1 tombstoned cancellation episode. Monthly burn of the live three = $D.
(`<backup-dir>/Otto-Export-2026-08-08.json` is the same bytes under the app's own filename. Do not rely on that name - an older export shares it.)

**Raw container backups, independent of the export format** - two SwiftData stores each (`default.store`, `OttoDeviceState.store`, plus `-wal`/`-shm`):

```
<backup-dir>/otto-container-backup-pre-install/          taken 21:15, before the Gate 2 build was installed
<backup-dir>/otto-container-backup-FINAL-pre-uninstall/  taken 22:28, immediately before the uninstall
```

⚠ **Read a COPY of these, never the originals.** `sqlite3` checkpoints and truncates a WAL-mode database's `-wal` the moment it opens it; the first backup's `-wal` already went 782 KB → 0 that way. No data was lost (it merged into the main file, `integrity_check` ok, 3 live subscriptions still present), but the originals are no longer byte-identical to the device.

**Device:** the owner's iPhone, iOS 26.x, UDID `<udid>`, CoreDevice id `<coredevice-id>`. Bundle id `com.arthurzhang.otto`. The **Release** build with the Gate 2 fixes was left installed, holding the partially-restored data described above.

## Steps to resume

The owner must do 1, 2 and 5 by hand - a file picker and a permission alert cannot be driven from the command line.

1. **AirDrop the verified file to the PHONE** (not the Mac - that is the mistake that voided the first run), and Save to Files somewhere that is not an Otto-scoped folder. Confirm the phone shows a 9,264-byte file of that name before importing.
2. **Import it with Replace.** The merge/replace prompt WILL appear this time, because the database is no longer empty. Do not accept a default.
3. **Verify the watermarks BEFORE granting notification permission.** This ordering is load-bearing: with `permission=notDetermined`, `reschedule` returns early and never touches the ledger, so the reconstructed values stay observable. Once permission is granted and a pass runs, watermarks legitimately advance to roughly today+104 days and the reconstruction can no longer be checked.

   ```
   xcrun devicectl device copy from --device <udid> \
     --domain-type appDataContainer --domain-identifier com.arthurzhang.otto \
     --source "/Library" --destination <dir>
   sqlite3 <dir>/Application\ Support/OttoDeviceState.store \
     "select * from ZSTOREDMATERIALIZATIONWATERMARK;"
   ```

   **Expected - one row per live subscription, each from the LEDGER or the anchor, never today:**
   - Subscription A → **<date-A>** (its latest live ledger row)
   - Subscription C → **<date-C>** (its anchor; no live ledger rows)
   - Subscription B → **<date-B>** (its anchor; no live ledger rows)

   **An empty table is a FAIL. Any watermark at or near the current date is the v2.1 failure signature and a FAIL.**
4. **Verify the record counts.** The verified file carries "Gate Test", so a Replace should take the container to **5 subscriptions / 12 events / 1 episode**, with live counts **3 / 3 / 1**. The re-derived import summary should read 3 subscriptions, 3 charges, 1 payment method - live records only; tombstones are counted nowhere by design (Wave 10, defect H).
5. **Grant notification permission**, reopen the app, then report the pending requests - **actual identifiers and trigger dates, never a count.** Launch with the console attached to read Otto's own log without root:

   ```
   DEVICECTL_CHILD_OS_ACTIVITY_DT_MODE=enable xcrun devicectl device process launch \
     --device <udid> --terminate-existing --console com.arthurzhang.otto
   ```

   Expect `permission=authorized`, one `[scheduling] ledger <uuid> watermark=<before>-><after>` line per live subscription, and a `[scheduling] reconcile ... added=[...]` line listing the identifiers as they are scheduled. For the pending set itself, attach LLDB (`device select "the owner's iPhone"` / `device process attach -p <pid>`) and call `getPendingNotificationRequestsWithCompletionHandler:`.

## The honest boundary to state when reporting it

This gate proves a **manual** export/restore floor exists. It does not prove any automatic protection, and §8's first CloudKit prerequisite - an automatic pre-enable export snapshot - is a different thing this does not satisfy.

Also state plainly: **the uninstall clears the notification permission, so reminders do NOT come back with the data.** They return only after the user re-grants and a scheduling pass runs. "My data came back" and "my reminders came back" are different promises, and only the first one is what this gate establishes.

## Two ⛔ defects found during Gate 3 that 6B must decide on

Both are recorded in §9a with full analysis; neither is fixed.

1. **An empty-database import silently skips watermark reconstruction** (above). One-word fix available; the better fix decouples the watermark policy from the merge strategy.
2. **Merge rules order on wall-clock timestamps, and the device clock is not monotonic** - found in real exported data, where two records carry a `deletedAt` PRECEDING their `createdAt`, written under the advanced clock of manual procedure 1. Seven code paths decide on `createdAt`/`updatedAt`; the two that matter are the import merge's record-level last-writer-wins and §5.3's earliest-`createdAt`-wins. Full analysis and three fix options in `docs/sync-safety.md`. **This one blocks 6B**, because CloudKit's own conflict resolution makes the same monotonicity assumption.
