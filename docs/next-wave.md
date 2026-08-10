Next wave: **6B - CloudKit activation**, specified in `docs/Subscription-Tracker-Spec.md` §8 (v2.6), gated on the manual checks in `docs/cloudkit-readiness.md`.
Wave 10 (Notification Delivery & Check-Date Fixes, from the Aug 2026 device run) landed in between; 6B remains the next planned wave.
Carry-over candidates for a later wave: simulator-hosted `NotificationCoordinator` tests (see `docs/implementation-notes/wave-10.md`, "Deliberately not done").

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
