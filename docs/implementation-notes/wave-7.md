# Wave 7 - Insights, payment methods, zombie detection

Date: 2026-08-07

The first wave under the v1.6 reorder: 7 and 8 now precede 6, because neither depends on CloudKit, both surface §5 model changes while those are still field additions, and export/import is the CloudKit escape hatch.
This wave also closes the one place code and spec knowingly disagreed: the §5.4 paused-cancellation defer-and-ask path.

## What exists after this wave

- **Spec v1.6** replaces v1.5 (`d97cfbd`): the pause-resume derivation rule, the device-local unsynced watermark, `expectedChargeAmountCents` corrected to optional, and the §9a known-issues section.
- **Pause resume is derived** (`0c03781`), closing the founding scenario's fourth escape route.
  `effectiveStatus(asOf:)` treats a `.paused` subscription past `pauseEndsOn` as `.active`; a dated pause materializes its resumed sequence even while paused (which is what makes advancing the watermark safe), and an indefinite pause freezes the watermark so a manual resume backfills from it.
  Invalidation mirrors materialization: pausing with a date tombstones only the rows inside the pause.
  A `PhoneInADrawerTests` case pins the scenario: paused until Sep 1, app never opened until Oct 15, both vendor charges have rows on wake.
  A persistence test pins that watermark writes never bump `updatedAt`.
- **The paused-cancellation defer-and-ask path** (`f5243ef`), spec §5.4 v1.5, previously specified but forbidden UI.
  `verificationCheckDate` is now pause-aware and OPTIONAL: a dated pause watches the first occurrence on or after `pauseEndsOn`; an indefinite pause returns nil and the flow writes an `.awaitingResumeDate` record with no date - never a fabricated one.
  `CancellationRecord.nextChargeDateIfNotCancelled` is now `CalendarDay?`, nil exactly while `.awaitingResumeDate` - enforced at construction, in Codable, and in the mapping layer.
  A deferred record generates no notifications, never escalates, refuses both verification answers (the yes-path must not archive an unverified cancellation), and surfaces as a Today needs-action card asking for the date; supplying it computes the check date and joins the ordinary pending watch.
- **A pause flow** (`f5243ef`): nothing in the app could actually enter `.paused` - Add/Edit deliberately preserves lifecycle states and no other UI existed - so the §5.4 paused path was unreachable.
  Detail now pauses (optional resume date, honest copy about what each choice means) and resumes; pausing a converted-unflipped trial writes the conversion through first, per derive-before-you-mutate.
- **`Subscription.pausedOn`** (`f5243ef`), both layers: §5.1 pins paused spend to "the price frozen when the pause began", which is uncomputable without knowing when that was.
  Set by the pause flow, cleared on resume; nil on rows paused before the field existed, where Insights falls back to the current price as the honest answer.
- **Insights** (`a34dd41`), spec §7.2, every figure a pure domain function tested against hand-computed fixtures: monthly burn and annualized total (all four cycle units, the 30.4375 half-cent boundary case), burn by category, the next-12-months projection (partial current month, annual clusters, trial paid sequences, dated-pause resumption), paused spend as its own line at the frozen price (a `PriceChange` during a pause does not move it), converting-soon trials with the cumulative consequence sentence, and the cross-subscription price-change log.
  Empty database, single subscription, and only-paused-or-cancelled databases all have pinned answers and useful empty states.
- **Zombie detection** (`a34dd41`), spec §7.3: `zombieReport` lists effectively-active subscriptions with no recorded use in 90+ days - the same cadence constant the check-in reminders use - with the cost over that window and the annual number.
  Facts, never a recommendation; converted-and-noticed-late trials appear costed from their conversion, which is the record the report exists for.
  The usage check-in notification finally has its responses (deferred from Wave 4): "still using it" records the use in the background, "not really" opens the facts; Detail gets "I used this today".
- **Payment methods** (`a34dd41`), spec §5.5: list, add, edit, soft delete; expiry warnings derived from the month-end rule with a 60-day window; per-card monthly totals computed by the same burn rules; a single-default invariant enforced at the store.
  Add/Edit creates a card inline - a label plus last4 is enough, a suggested label covers the cheap path, and the saved card selects itself in the picker.
- **Tabs**: Insights and Payment methods join Today and Subscriptions; the Dynamic Type suite covers the new rows (zombie, converting-soon, payment method) at accessibility sizes.

## verify.sh against this wave's HEAD

Passed clean: OttoDomain 173, OttoPersistence 68, OttoUI 99 - 340 on the mac host, plus 7 Dynamic Type tests that exist only on a simulator (verified locally via `xcodebuild test -scheme OttoUI-Package`), 347 total.
The Wave 5.5 segfault did not recur in this wave's runs.

## Findings and deviations (not polite)

1. **§5.1's table needs a `pausedOn` row in v1.7.**
   The frozen-price formula was pinned in v1.1 and has been uncomputable ever since, because no field records when a pause began.
   This is exactly the §5 gap class the reorder exists to catch before the CloudKit cliff.
2. **§5.4's table says `nextChargeDateIfNotCancelled` is non-optional; the code now says `CalendarDay?`.**
   The defer-and-ask path the same section specifies REQUIRES an absent date - the v1.1 rationale for non-optionality (no derivable fallback) is precisely why the deferred state must store nothing.
   v1.7 should record the pairing invariant: nil exactly while `.awaitingResumeDate`.
3. **The spec has no pause flow anywhere in §7.1's screen list**, yet §5.1 makes paused first-class and §5.4 legislates cancelling from it.
   A minimal one now exists in Detail; v1.7 should either adopt it into the screen list or say where pausing actually lives.
4. **The watermark still physically lives on `StoredSubscription`.**
   v1.6 decided it is device-local and stored outside the CloudKit-backed schema, but SwiftData cannot exclude a single property from sync - Wave 6 must move it into a separate non-synced `ModelConfiguration` as its FIRST schema act, and Wave 8's export should exclude it (it describes a device, not the data).
5. **Editing `pauseEndsOn` backwards can still strand charges.**
   A pass during a pause-until-December advances the watermark; the user then editing the resume date back to September leaves Sep-Nov behind a watermark that vouches for no rows.
   This is the edit-rewrites-history class, not the drawer class; it needs a spec decision (likely: a pause-date edit rewinds the watermark to `min(watermark, new pauseEndsOn)`).
6. **Zombie cost uses the current effective amount across the whole window.**
   A price change mid-window slightly misstates the cost since last use; computing from `PriceChange` history would be exact.
   Chosen for simplicity and stated here rather than hidden.
7. **The burn assumes one currency.**
   `monthlyBurnCents` sums cents across subscriptions; v1 is CAD-only so this is safe today, but the first USD subscription would be silently added to CAD totals.
   §7.2 should say what multi-currency burn even means before any such subscription can exist.
8. **Interpretations this wave had to make** (each tested, none spec-backed): the next-12-months window counts only the current month's REMAINING charges; consecutive converting-soon sentences chain cumulatively so two trials never contradict; a never-used subscription's zombie window includes its anchor charge while a recorded use excludes the use day itself; the card-expiry warning window is 60 days; a card is valid through the end of its printed month.
9. **`caughtUpCancellationRecords` and `SubscriptionsStore.refresh` filter by STORED status** when collecting cancellation records.
   Correct today - every path into a cancellation state writes the stored status - but it is the kind of stored-vs-effective read that produced the Wave 4 bug, and a future derived cancellation state would slip past both.

## Still on the owner

1. The Android-or-public-distribution decision - Wave 6 remains blocked on it, and the reorder bought Waves 7 and 8 of time, not more.
2. The three manual device checks in `docs/manual-verification.md`; the compressed-timeline trial test is still the unmet ⛔ gate.
3. The GitHub remote - CI has still never executed, and the only genuinely unverified thing in it is the `macos-26` runner label.
   ⚠ **Corrected at Gate 1 (Aug 2026): wrong on the second half.** `macos-26` was correct; the first run found two test defects that depended on the host machine rather than on the app. See `DECISIONS.md`, "Gate 1".
