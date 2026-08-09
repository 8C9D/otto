# Manual device verification

Three checks need a real phone and a human; no test target can discharge them.
Each is a numbered checklist with an explicit pass criterion per step - a check without a criterion is an anecdote, not a verification.
Run them on a physical iPhone with the app installed from Xcode (`xcodegen generate`, open `Otto.xcodeproj`, run the `Otto` scheme on the device).

Notification timing facts these procedures rely on (from `FireTimePolicy.standard`): everything fires at 09:00 local except the trial evening last-call at 19:00.
A trial's cancel-by day is `conversionDate - bufferDays`, and its conversion day is `startDate + lengthDays`.

Record the outcome of each run (date, device, iOS version, pass/fail per step) at the bottom of this file.

## Clock-manipulation rules (learned the hard way, Aug 2026 run)

The first attempt at the Wave 5 gate failed, and the cause was this procedure, not Otto: the old step 8 said to pause "~2 minutes past 09:00" of each advanced day, which lands the clock PAST every fire hour.
**iOS does not deliver a non-repeating `UNCalendarNotificationTrigger` whose fire instant was jumped over** - Otto had scheduled correctly and iOS held the right trigger for two device-days; the jump killed it.

- **Never let the clock land past a fire time. Always set it to a few minutes BEFORE the fire time and let it tick through.**
  Real clocks tick; they never jump. The actual phone-in-a-drawer path was never at risk - only the simulation was dishonest.
- **A dead trigger can resurrect, but only while a sibling timer is still live.**
  A clock change makes iOS recompute timers only for apps that still have an armed timer; once an app's last pending trigger dies, no rewind can reach it.
  Recovery then requires a device reboot, which makes SpringBoard reload every app's pending repository from disk.
  Generalized: **jumping past the last rung of a ladder is unrecoverable by clock manipulation alone.**
- Restoring automatic time at teardown moves the clock BACKWARDS across every advanced day.
  Observed in the run: the device moved back two days against a ledger materialized out to November, and rewrote nothing - display and scheduling stayed derived from the stored calendar days, exactly as §4.1 intends.
  Expect it, and do not file the time jump itself as a defect.

## 1. Compressed-timeline trial test (⛔ the Wave 5 gate)

Proves the full trial lifecycle on a device in about an hour by backdating the trial's start and advancing the device clock, instead of waiting two weeks.

**Setup**

1. Delete Otto from the device if present, then install fresh from Xcode. Pass: first launch shows an empty Today.
2. Allow notifications when prompted. Pass: iOS Settings → Otto → Notifications shows Allow Notifications on, and Time Sensitive on.
3. Settings → General → Date & Time: turn off "Set Automatically". Pass: the date can be changed by hand. (Re-enable it in step 15 - leaving it off breaks everything else on the phone.)

**Trial entry - cancel-by lands today**

4. Before 18:30 local, add a subscription as a trial: name "Gate Test", price 15.99, monthly, trial length 14 days, buffer 2 days, start date 12 days ago. Pass: the form shows cancel-by = today and conversion = the day after tomorrow, live, before saving.
5. Save and open the detail screen. Pass: status shows trial, cancel-by today, conversion in 2 days.
6. Lock the phone and wait for 19:00 (or set the clock to 18:59 and wait a minute). Pass: the evening last-call notification fires at 19:00 on the lock screen, names "Gate Test", and offers the three reminder actions (Keeping it / I'm cancelling / Remind me later) on long-press.

**Conversion with the app closed - the founding scenario**

7. Do NOT open the app again. Force-quit it (swipe up from the app switcher).
8. Advance the device clock one day at a time to the conversion day, setting it to **08:55 of each advanced day and waiting through 09:00** (never landing past a fire time - see the clock-manipulation rules above). Pass: the daily escalation fires on the day between cancel-by and conversion, and the conversion announcement fires at 09:00 on the conversion morning, on the locked screen - all with the app never opened.
9. Advance the clock 3 more days past conversion (08:55, tick through, each day), app still closed. Pass: no trial-deadline notifications fire after conversion (deadlines that are history stay silent).

**Wake - derivation, ledger, confirm**

10. Open the app. Pass: Today shows the converted-and-unacknowledged card for "Gate Test"; the subscription reads as active at the converted price (15.99), even though no flow ever ran.
11. Open detail and check the ledger. Pass: a charge row exists dated exactly the conversion day at 15.99 - created retroactively by the v1.5 watermark even though the app was closed when the date passed.
12. Confirm the conversion from the card. Pass: the card clears; the price history shows a trial-conversion entry; re-tapping confirm does nothing (idempotent).

**Cancellation after conversion - the Wave 4 bug's path, and defect G's (as actually run, Aug 2026)**

13. Start a cancellation from detail, on the conversion day itself. Pass: the verification watch date is the first monthly date counted from the CONVERSION day and **strictly after the cancellation day** - cancelling on the conversion day must watch NEXT month's date, never today's conversion charge, which landed legitimately before the cancellation (Wave 10, defect G; the Aug 2026 run watched "today" and produced a dispute summary a bank would reject).
14. Check the record (detail cancellation section). Pass: the recorded expected charge amount is 15.99, the converted price, not any later edit - and the ledger holds ONE row for the conversion day, not an Expected/Unexpected pair.

**Teardown (as actually run)**

15. Settings → General → Date & Time: turn "Set Automatically" back on. Pass: the clock is correct again - and note it moves BACKWARDS across every advanced day (two days in the Aug 2026 run, against a ledger materialized to November) while display and scheduling stay derived from stored calendar days; nothing is rewritten.
16. Delete "Gate Test" (or the app). Pass: Today is empty again, and no orphaned Gate Test notification fires later.

The gate is met only if every step above passed in one uninterrupted run.
A partial pass is a fail; note which step broke and file it against the wave.

## Device tooling notes (Aug 2026 run)

The whole procedure below can run from the command line; Xcode's GUI is not required.
Two failures in this session named nothing about their actual cause, and both were the same thing - **the phone was locked**:

- `devicectl device process launch` fails with `FBSOpenApplicationErrorDomain error 7`, which at least says "was not, or could not be, unlocked".
- **`log collect` fails with `Operation not supported (45)`, which names nothing at all.** If either appears, unlock the phone before diagnosing anything else. Set Auto-Lock to Never for the duration.

Other facts worth not rediscovering:

- `log collect --device-udid <udid>` needs **root** (`sudo`); without it you get "Must be root to collect logs from attached device". `log stream --device-name` does not exist on macOS 15.
- Otto's `os_log` output can be read WITHOUT root by launching through `xcrun devicectl device process launch --console` with `DEVICECTL_CHILD_OS_ACTIVITY_DT_MODE=enable` in the environment, which mirrors the unified log to the console. Use the archive when you need the SYSTEM's side (`dasd`, `BackgroundTasks`) as well as Otto's.
- `zsh` has its own `log` builtin - use `/usr/bin/log`.
- LLDB attaches over CoreDevice with `device select "<device name>"` then `device process attach -p <pid>`. Attaching STOPS the process, so `process interrupt` afterwards errors. Quitting LLDB without `detach` kills the app.

## 2. BGAppRefreshTask observation under LLDB

Proves the background refresh task actually registers, runs, completes, and re-arms - the path that keeps reminders honest when the app is never opened.
`_simulateLaunchForTaskWithIdentifier:` is a private debugger-only hook; this procedure only works on a device attached to a debugger.

⚠ **Registration is not execution, and this procedure exists because the difference was load-bearing.**
Before Aug 2026 the task had only ever been observed to REGISTER. It had never run, and when it was finally made to run it **crashed the app every time** (see the run log). A step that stops at "the identifier was accepted" would have passed on a completely dead path.
**The pass criterion for step 4 is a log line from inside the handler body, not the absence of an error.**

1. Run Otto on the device from Xcode with the debugger attached. Pass: the app launches with the console visible.
2. Set a breakpoint in `NotificationCoordinator.handleBackgroundRefresh(_:)`. Pass: the breakpoint resolves (solid blue).
3. Background the app (home swipe), then pause execution in Xcode (Debug → Pause). Pass: LLDB prompt appears.
4. In LLDB, run:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.arthurzhang.otto.refresh"]`
   then resume.
   Pass: **`[background] launched id=com.arthurzhang.otto.refresh` appears in the log.** Acceptance of the identifier is NOT the criterion - the identifier was accepted on every crashing run too.
5. Read the rest of the pass in the log. Pass, all four:
   - `[scheduling] pass begin trigger=backgroundRefresh` - the trigger is named, so a background wake cannot be confused with a foreground open;
   - one `[scheduling] ledger <uuid> watermark=<before>-><after>` line per live subscription;
   - `[scheduling] reconcile pending=N desired=N ... removed=[...] added=[...]` - **over an unchanged plan both lists must be empty while `pending` is not.** A remove-all would list every pending identifier as removed, which is how this line distinguishes Wave 10's diff from the shape it replaced;
   - `[background] completing path=normal success=true`.
6. Force expiration mid-pass. A breakpoint is needed because the pass finishes in ~40 ms, far faster than two hand-typed commands: set one inside the pass (`breakpoint set -r "reconcileLedger"`), simulate the launch, continue until it hits, then run
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.arthurzhang.otto.refresh"]`
   and continue.
   Pass, both halves: `[background] completing path=expiration success=false` appears **and no `path=normal` line follows it** (completion happened exactly once), **and** the pass is seen to actually stop - `[scheduling] ledger pass cancelled`, then `pass threw ... error=CancellationError`, then `[background] pass returned after expiration had already completed the task`.
   That last line is not a failure; it is the pass reporting that it outlived its expiration and declined to complete the task a second time. **If it ever appears far behind the expiration timestamp** (it was 0.9 ms in the Aug 2026 run), the checkpoints have become too sparse for the work between them.
7. Verify re-arming. Pass: `[background] re-armed earliestBegin=+24h` is logged from inside the handler, and the system side agrees - in a `log collect` archive, `dasd` records `Submitted: bgRefresh-com.arthurzhang.otto.refresh:<id> at priority 10 (<24h window>)`.

## 3. Hands-on add-a-subscription pass

The basic product loop, by hand, on the device - unsigned-off since Wave 3.

1. Add a subscription in mode A (start date): name "Netflix", 20.99 monthly, started on the 15th of some past month, lead 3 days. Pass: detail shows the next billing date on the coming 15th, computed live before saving.
2. Add one in mode B (next charge date): pick a date that is the 30th of next month. Pass: if the date is month-end-ambiguous the last-day question appears; answering changes the stored anchor accordingly.
3. Check Today. Pass: both subscriptions appear with correct next-charge dates and the monthly total is the sum of both prices.
4. Check pending reminders: background the app until the next 09:00, or check that Detail's coverage line claims coverage through a plausible horizon. Pass: a renewal reminder is scheduled 3 days ahead of the next charge (fires at 09:00 if you let it arrive).
5. Edit the Netflix price to 22.99. Pass: detail's price history shows the old and new price as an appended entry - not an overwrite.
6. Toggle a Dynamic Type size at the largest accessibility setting (Settings → Accessibility → Display & Text Size → Larger Text, max). Pass: the list rows and Today cards grow without truncating any label.
7. Delete both subscriptions. Pass: Today returns to empty with no orphaned reminders firing later (spot-check: no Otto notification arrives the next morning).

## 4. Data survives delete-and-reinstall (⛔ the 6B floor)

Proves a manual export/restore floor exists before CloudKit does. It destroys the container deliberately, so the ordering below is not optional.

**⚠ The export must be on the DEVICE THAT WILL IMPORT IT.**
The Aug 2026 run lost an hour to this: the fresh export was AirDropped to the *Mac* for verification, so it was never in the *phone's* file picker, and the import silently used an older export already sitting in Files.
Verifying a file on the Mac verifies nothing about the file the phone will offer you. **AirDrop to the phone, and separately copy to the Mac if you want to verify it there.**

**⚠ Name the file by `sha256` on both sides.** Take the hash on the Mac, and confirm the phone is importing a file of that same name and size before tapping import. "The export" is not an identifier; a hash is.

1. Export from the app (Share → Save to Files ON THE PHONE), then AirDrop a copy to the Mac. Record `shasum -a 256 <file>`. Pass: the hash is written down.
2. Verify the Mac copy parses: `formatVersion` 4, the expected number of LIVE subscriptions, amounts, anchors, and a monthly burn that reconciles by hand. Pass: every number matches what the app shows.
3. Take a raw container backup as an independent second copy - `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.arthurzhang.otto --source "/Library"`. Pass: `default.store` and `OttoDeviceState.store` arrive.
   Copying `/` fails on a metadata plist; copy `/Library` instead. **Read the copy, never the original** - `sqlite3` checkpoints and truncates a WAL-mode database's `-wal` on open, so querying a backup mutates it.
4. `xcrun devicectl device uninstall app`. Pass: a container copy afterwards fails with `ContainerLookupErrorDomain error -1` and retrieves zero files. An app that merely vanished from the home screen is not proof.
5. Reinstall and launch. Pass: `[scheduling] pass end ... permission=notDetermined scheduled=0` with **no ledger lines at all**, and the container reads 0 subscriptions. Confirm on screen: "No subscriptions yet" and the Wave 9A permission banner.
6. Import the hashed export **with Replace**. Pass: the summary states live records only (3 subscriptions / 3 charges / 1 payment method for the Aug 2026 data).
   ⚠ **Do not accept the default.** An import into an empty database runs `.merge` without asking, and `.merge` skips watermark reconstruction (§9a). Since the empty database IS the recovery case, the default path is the wrong one until that is fixed.
7. Verify the data: correct amounts, correct next-charge anchors, monthly burn reconciling to the pre-uninstall figure, and the payment method reading "N subscriptions billed to this card".
8. **Verify the watermarks reconstructed from the LEDGER, never from today.** Pass: `ZSTOREDMATERIALIZATIONWATERMARK` holds one row per live subscription, each equal to the latest live expected date for that subscription or its anchor when it has none. An empty table is a FAIL, not a neutral state. An annual subscription showing a next charge near today is the failure signature.
9. Grant notification permission, then reopen. Pass: `permission=authorized`, one `[scheduling] ledger <uuid> watermark=…` line per live subscription, and `getPendingNotificationRequests` listing real identifiers with their trigger dates - report the identifiers, never a count.
   **Note the honest boundary: the uninstall clears the notification permission, so reminders do NOT return with the data.** They return only after the user re-grants and a pass runs. "My data came back" and "my reminders came back" are different promises.

**What this gate proves and does not.** It establishes a MANUAL export/restore floor. It does not prove any automatic protection, and §8's first CloudKit prerequisite - an automatic pre-enable export snapshot - is a different thing this does not satisfy.

## Run log

| Date | Procedure | Device / iOS | Result | Notes |
|---|---|---|---|---|
| 2026-08-08 | 2 (BGAppRefreshTask) | a physical iPhone, iOS 26.x | ⛔ **FAIL, then PASS after a one-line fix** | First observation of the handler ever running. It crashed, every time: `register(using: nil)` puts the launch handler on a background queue, the closure is `@MainActor`-isolated, and Swift 6's runtime isolation check trapped in `_dispatch_assert_queue_fail` before the first line of the body - so `setTaskCompleted` was never reached on any path. Three system crash reports, faulting queue `com.apple.BGTaskScheduler (com.arthurzhang.otto.refresh)`. Fixed by `using: .main`; re-verified in **both Debug and Release**: handler body runs, `trigger=backgroundRefresh`, watermarks steady, `removed=[] added=[]` over 7 pending, `path=normal success=true`. Fixing that exposed a second defect the crash had been hiding - expiration completed the task while the pass ran on and completed it again - fixed the same session with a completion latch and cancellation checkpoints, re-verified on both configurations. |
| 2026-08-08..10 (device days) | 1 (compressed trial) | physical iPhone | ⛔ gate PASS on 2nd attempt | 1st attempt failed on the procedure (old step 8 jumped past fire times; rules above added). Gate criterion met: conversion announcement fired 09:00 on a locked screen, app never opened since entry two device-days earlier. Four code defects found in the same run (G, B, A, C) plus fixture/display gaps (D, H, I, J) - all fixed in Wave 10. |
