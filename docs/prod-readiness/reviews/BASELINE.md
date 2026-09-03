# BASELINE — Otto production-readiness sweep

Captured 2026-08-10 against commit `406a5a686d1c6b67d251ba38c36545ebbb772ff3` (branch `prod-readiness/2026-08-10`, identical tree to `main` at `406a5a6`).

Working tree was clean at preflight. No commits precede this file on the branch.

## What was run

Two commands, both on this host, both from the committed HEAD.

1. `scripts/verify.sh` — the canonical local verification (project generation, every package's tests, the app build, SwiftLint `--strict`). **Note: the prompt for this run says `verify.sh` is at the repo root. It is not; it is at `scripts/verify.sh`.**
2. `xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"` (iPhone 16 Pro simulator) — the UIKit-hosted Dynamic Type / empty-state suites, which compile to nothing under `swift test` on a mac host and are therefore not covered by `verify.sh`.

## Result: BOTH GREEN. No pre-existing failures.

- `verify.sh` exit 0 — OttoDomain 246, OttoPersistence 112, OttoUI 168, **total 526 tests**.
- Simulator suite exit 0 — `** TEST SUCCEEDED **`, **19 tests in 3 suites**, *with 7 recorded "known issues"* (see the environment section below — these are not failures, and they are not clean either).

Every later "green build" claim in this run is measured against these two numbers: **526 host tests, 19 simulator tests, lint clean under `--strict`.**

## `verify.sh` clones the code, not the environment

`verify.sh` clones the committed HEAD into a temp directory and tests that. What it cannot vary is the machine: it runs in the same locale, the same region, the same calendar, and on the same hardware as the working tree it is trying to be independent of. It is independence from *the working tree*, not from *the host*.

CI has already found two defects of exactly the kind no clean-clone run on one machine could catch — a locale-dependent assertion and an accessibility-tree suite with no AX client. Both were host-environment dependencies, and `verify.sh` was green for both.

**This run observed the following environments and no others:**

| Dimension | Observed value | Not observed |
|---|---|---|
| Host | macOS 24.6.0, arm64, Xcode 26 | any other toolchain |
| Locale / region | the host's own (en_CA-family, `$` currency rendering) | every other locale |
| Device calendar | Gregorian (host default) | Buddhist, Japanese, Hebrew, Islamic, Republic-of-China |
| Time zone | America/Toronto | every other zone |
| Runtime | iOS **Simulator** only | **physical device — prohibited this run** |
| Configuration | **Debug** only | **Release — not built or run this run** |
| Accessibility | **no AX client on this host** | a host with a usable AX tree |

Per-finding, this run says which of these it actually observed. Anything only confirmable on hardware is **UNVERIFIED by construction**, because touching the device is prohibited.

### The 7 "known issues" in the simulator suite

`EmptyStateTests` asserts on rendered accessibility labels. On this host UIKit vends none (`scenes=0 elements=45 labels=0 blank=false`), so those assertions record known issues rather than passing or failing. The suite reports `** TEST SUCCEEDED **` anyway.

This means: **the string assertions in `EmptyStateTests` were not exercised in this run's baseline and cannot be exercised on this host.** A regression in that copy would not be caught here. That is a property of the environment, not a defect in the tests — but a green simulator run on this machine is weaker evidence than the exit code suggests, and this file records that so no later claim can lean on it.

## ⚠ CONTAMINATION DISCLOSURE — Stage 0's "do not read prior findings" instruction was violated by Stage 0's own mandated command

Stage 0 instructs: *"Do not read the project's existing defect lists before writing your ledger… Deliberately do not consult it during Stage 0."*

Stage 0 also instructs: *"This project has `verify.sh` … Run it, plus the simulator test suite, and commit the raw output."*

**`scripts/verify.sh` ends by printing `docs/next-wave.md` in full** (script lines 108–125; README, "Verifying a wave"). `docs/next-wave.md` is ~90 lines and contains a section headed `# ⛔ RESUME HERE: Gate 3 … is PAUSED, PART-MET`, including a subsection titled **"Two ⛔ defects found during Gate 3 that 6B must decide on"**, each with file:line evidence.

So running the command Stage 0 requires disclosed the defect list Stage 0 forbids. The two instructions are mutually unsatisfiable as written. This was unavoidable and is disclosed rather than concealed.

**Specifically seeded into this run before any finding was written:**

1. *An empty-database import silently skips watermark reconstruction* — cited to `SettingsView.swift:293`.
2. *Merge rules order on wall-clock timestamps and the device clock is not monotonic* — cited to `docs/sync-safety.md`, described as blocking Wave 6B.

Plus operational context: Gate 2 (`BGAppRefreshTask`) is met; Gate 3 is paused; CI, not `verify.sh`, is the real gate.

**A second, independent contamination:** this session's persistent memory carried a note titled *"Otto gate clock-jump diagnosis"* naming two residual items — *reschedule actor reentrancy* and *untested `NotificationCoordinator`*. That was in context before the repository was opened.

Every ledger finding is tagged `INDEPENDENT` or `CONTAMINATED` accordingly. A `CONTAMINATED` finding proves nothing about whether an independent sweep would have found it, and this run does not claim otherwise.

## Raw output — `scripts/verify.sh`

```
== Otto verify: committed HEAD 406a5a686d1c6b67d251ba38c36545ebbb772ff3
== Working tree state is deliberately ignored; only the clone is tested.
== packages (derived from the clone's Packages/): OttoDomain OttoPersistence OttoUI
== xcodegen generate
== swift test: OttoDomain
== swift test: OttoPersistence
== swift test: OttoUI
== xcodebuild: app target (simulator, unsigned)
== swiftlint --strict

== VERIFIED: 406a5a686d1c6b67d251ba38c36545ebbb772ff3 builds, tests, and lints from a clean clone
   OttoDomain: 246
   OttoPersistence: 112
   OttoUI: 168
   total: 526 tests

   NOT counted: the OttoUI Dynamic Type suite is UIKit-hosted and compiles
   to nothing under swift test on a mac host. It runs only on a simulator
   (the CI simulator job, or xcodebuild test locally) - do not report its
   tests as covered by this script's total.

== NEXT WAVE (docs/next-wave.md - update it as part of landing a wave):
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
   
   the owner must do 1, 2 and 5 by hand - a file picker and a permission alert cannot be driven from the command line.
   
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
```

## Raw output — simulator suite (tail; full log was 
    1605 lines)

```
Test Suite 'All tests' started at 2026-08-10 19:19:04.878.
Test Suite 'All tests' passed at 2026-08-10 19:19:04.879.
✔ Test run with 97 tests in 18 suites passed after 0.205 seconds.
Test Suite 'All tests' started at 2026-08-10 19:19:05.802.
Test Suite 'All tests' passed at 2026-08-10 19:19:05.802.
✔ Test run with 64 tests in 10 suites passed after 0.066 seconds.
Test Suite 'All tests' started at 2026-08-10 19:19:06.574.
Test Suite 'All tests' passed at 2026-08-10 19:19:06.574.
✘ Test "the payment-method row's RENDERED copy is inflected - no morphology residue (defect I, view level)" recorded a known issue at EmptyStateTests.swift:295:23: Expectation failed: labels.contains { $0.contains(text) }
✘ Test "the payment-method row's RENDERED copy is inflected - no morphology residue (defect I, view level)" passed after 2.269 seconds with 1 known issue.
✘ Test "⛔ the clear-filter action WORKS: activating it clears the filter and the rows come back" recorded a known issue at EmptyStateTests.swift:254:29: Issue recorded
✘ Test "⛔ the clear-filter action WORKS: activating it clears the filter and the rows come back" passed after 2.657 seconds with 1 known issue.
✘ Test "⛔ a filter that matches nothing renders the named empty state, not a blank screen" recorded a known issue at EmptyStateTests.swift:211:23: Expectation failed: labels.contains { $0.contains(text) }
✘ Test "⛔ a filter that matches nothing renders the named empty state, not a blank screen" recorded a known issue at EmptyStateTests.swift:211:23: Expectation failed: labels.contains { $0.contains(text) }
✘ Test "⛔ a filter that matches nothing renders the named empty state, not a blank screen" recorded a known issue at EmptyStateTests.swift:211:23: Expectation failed: labels.contains { $0.contains(text) }
✘ Test "⛔ a filter that matches nothing renders the named empty state, not a blank screen" passed after 2.951 seconds with 3 known issues.
✘ Test "the unfiltered empty list still says 'No subscriptions yet' with its Add action" recorded a known issue at EmptyStateTests.swift:235:23: Expectation failed: labels.contains { $0.contains(text) }
✘ Test "the unfiltered empty list still says 'No subscriptions yet' with its Add action" recorded a known issue at EmptyStateTests.swift:235:23: Expectation failed: labels.contains { $0.contains(text) }
✘ Test "the unfiltered empty list still says 'No subscriptions yet' with its Add action" passed after 3.021 seconds with 2 known issues.
✘ Suite "Subscriptions list empty states (Wave 10, defect J)" passed after 3.022 seconds with 7 known issues.
✘ Test run with 19 tests in 3 suites passed after 3.022 seconds with 7 known issues.
** TEST SUCCEEDED **
```
