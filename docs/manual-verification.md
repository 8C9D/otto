# Manual device verification

Three checks need a real phone and a human; no test target can discharge them.
Each is a numbered checklist with an explicit pass criterion per step - a check without a criterion is an anecdote, not a verification.
Run them on a physical iPhone with the app installed from Xcode (`xcodegen generate`, open `Otto.xcodeproj`, run the `Otto` scheme on the device).

Notification timing facts these procedures rely on (from `FireTimePolicy.standard`): everything fires at 09:00 local except the trial evening last-call at 19:00.
A trial's cancel-by day is `conversionDate - bufferDays`, and its conversion day is `startDate + lengthDays`.

Record the outcome of each run (date, device, iOS version, pass/fail per step) at the bottom of this file.

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
8. Advance the device clock one day at a time to the conversion day, pausing ~2 minutes past 09:00 of each advanced day. Pass: the daily escalation fires on the day between cancel-by and conversion, and the conversion announcement fires on the conversion morning - all with the app never opened.
9. Advance the clock 3 more days past conversion, app still closed. Pass: no trial-deadline notifications fire after conversion (deadlines that are history stay silent).

**Wake - derivation, ledger, confirm**

10. Open the app. Pass: Today shows the converted-and-unacknowledged card for "Gate Test"; the subscription reads as active at the converted price (15.99), even though no flow ever ran.
11. Open detail and check the ledger. Pass: a charge row exists dated exactly the conversion day at 15.99 - created retroactively by the v1.5 watermark even though the app was closed when the date passed.
12. Confirm the conversion from the card. Pass: the card clears; the price history shows a trial-conversion entry; re-tapping confirm does nothing (idempotent).

**Cancellation after conversion - the Wave 4 bug's exact path**

13. Start a cancellation from detail. Pass: the verification watch date shown is the first monthly date counted from the CONVERSION day, not from the trial start day, and not next month's wrong anniversary.
14. Check the record (detail cancellation section). Pass: the recorded expected charge amount is 15.99, the converted price, not any later edit.

**Teardown**

15. Settings → General → Date & Time: turn "Set Automatically" back on. Pass: the clock is correct again.
16. Delete "Gate Test" (or the app). Pass: Today is empty again.

The gate is met only if every step above passed in one uninterrupted run.
A partial pass is a fail; note which step broke and file it against the wave.

## 2. BGAppRefreshTask observation under LLDB

Proves the background refresh task actually registers, runs, completes, and re-arms - the path that keeps reminders honest when the app is never opened.
`_simulateLaunchForTaskWithIdentifier:` is a private debugger-only hook; this procedure only works on a device attached to Xcode, in a debug build.

1. Run Otto on the device from Xcode with the debugger attached. Pass: the app launches with the console visible.
2. Set a breakpoint in `NotificationCoordinator.handleBackgroundRefresh(_:)`. Pass: the breakpoint resolves (solid blue).
3. Background the app (home swipe), then pause execution in Xcode (Debug → Pause). Pass: LLDB prompt appears.
4. In LLDB, run:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.arthurzhang.otto.refresh"]`
   then resume. Pass: the identifier is accepted (no "unregistered identifier" error in the console) and the breakpoint from step 2 hits.
5. Continue past the breakpoint. Pass: the console shows the pass completing and `setTaskCompleted(success:)` is reached - no expiration warning is logged.
6. Pause again and run:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.arthurzhang.otto.refresh"]`
   Pass: the expiration handler runs without crashing and the task still ends via `setTaskCompleted`.
7. Verify re-arming: after step 5, pause and inspect pending requests:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] getPendingTaskRequestsWithCompletionHandler:^(NSArray *r){ NSLog(@"pending: %@", r); }]`
   Pass: the log lists a pending `com.arthurzhang.otto.refresh` request - each run schedules the next.

## 3. Hands-on add-a-subscription pass

The basic product loop, by hand, on the device - unsigned-off since Wave 3.

1. Add a subscription in mode A (start date): name "Netflix", 20.99 monthly, started on the 15th of some past month, lead 3 days. Pass: detail shows the next billing date on the coming 15th, computed live before saving.
2. Add one in mode B (next charge date): pick a date that is the 30th of next month. Pass: if the date is month-end-ambiguous the last-day question appears; answering changes the stored anchor accordingly.
3. Check Today. Pass: both subscriptions appear with correct next-charge dates and the monthly total is the sum of both prices.
4. Check pending reminders: background the app until the next 09:00, or check that Detail's coverage line claims coverage through a plausible horizon. Pass: a renewal reminder is scheduled 3 days ahead of the next charge (fires at 09:00 if you let it arrive).
5. Edit the Netflix price to 22.99. Pass: detail's price history shows the old and new price as an appended entry - not an overwrite.
6. Toggle a Dynamic Type size at the largest accessibility setting (Settings → Accessibility → Display & Text Size → Larger Text, max). Pass: the list rows and Today cards grow without truncating any label.
7. Delete both subscriptions. Pass: Today returns to empty with no orphaned reminders firing later (spot-check: no Otto notification arrives the next morning).

## Run log

| Date | Procedure | Device / iOS | Result | Notes |
|---|---|---|---|---|
