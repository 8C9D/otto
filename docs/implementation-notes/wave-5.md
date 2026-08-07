# Wave 5 - the trial, cancellation, and verification flows

Date: 2026-08-07

## What exists after this wave

- **A broken-baseline fix, first** (`30e2e99`): commit `388edb2` changed `NotificationPlanIdentifier.snooze` to carry the origin kind but never updated the domain test calling it, so `OttoDomain`'s test suite did not compile at Wave 4's HEAD.
  Wave 4's "203 tests passing" was not reproducible as committed.
  The call was updated to the new signature (and now also asserts the kind round-trips); nothing was weakened.
- **The spec v1.4 reconciliation** (`6f0b7a6`, `6bc12fa`), before any Wave 5 code:
  - `BillingEvent.acknowledgedAt` in both layers, written by the action handler through the flow service, honoured by the planner: `reminderSchedule` takes `acknowledgedChargeDays` and skips the lead, same-day, and catch-up reminders for an acknowledged charge - and a trial whose conversion event is acknowledged keeps only the announcement rung.
    The regression test the spec asked for first ("Keeping it" then three full reschedules) is `keepingItSurvivesFullReschedule`.
  - §5.3's materialization/invalidation decisions moved from `OttoStore` into the domain (`expectedCharges`, `isExpectedCharge`), which is also where the v1.4 status-transition generalization landed: transitions into `.paused`, `.cancellationPending`, `.cancelled`, and `.archived` invalidate every `.upcoming` row, and resuming re-materializes.
    The services-test fake ledger now runs the same domain decisions as the real store instead of returning `[]`.
  - §5.2b's "loudly": `SubscriptionRepository.unreadableSubscriptionCount()`, surfaced by `SubscriptionsStore` and rendered as ONE aggregate needs-review card at the top of Today.
  - §6.2: `BillingCycle.isCovered(byLeadDays:)` and a non-blocking Add/Edit warning when the lead spans a whole cycle. The single-catch-up rule itself already existed in Wave 4's planner; v1.4 adopted it as written.
- **The flow service** (`SubscriptionFlowService`, layer 4): trial confirmation, "Keeping it", cancellation start, evidence updates, and verification answers, in one actor.
  The notification handler delegates to it and the screens reach it through `AppModel`, so the two entry points produce identical state by construction - and `entryPointsProduceIdenticalState` proves it anyway, byte-comparing subscriptions, records, events, and pending notification identifiers across two worlds.
- **The trial flow**: the converted-unacknowledged card (Wave 4's `trialConverted` entry) now has its confirm action.
  `Subscription.confirmingConversion(asOf:at:)` builds the persisted flip §5.2a permits - `.active`, anchored at the conversion date, at the converted amount, **trial term retained**.
  Confirming acknowledges the conversion ledger row (creating it retrospectively if the conversion predates the first materializing pass - see findings) and appends a `PriceChange` with the new `.trialConversion` source.
  Idempotent because the flip is last: once flipped, `confirmingConversion` returns nil and the method is a no-op.
- **The cancellation flow**: `CancellationFlowView` (detail-screen entry) and the §6.4 notification action share `startCancellation`, which creates the record BEFORE flipping the status - an interruption leaves a dormant record beside an active subscription, never `.cancellationPending` with nothing watching it.
  The check date comes from the new domain `verificationCheckDate`/`nextWouldBeChargeDate`, which is trial-aware by term rather than by status.
  Evidence (confirmation number + notes) is captured at start or added later; redelivery never overwrites it, deliberate edits go through `updateCancellationEvidence`.
- **The verification flow**: verification notifications now carry the yes/no actions (`otto.category.verification`; "No" is foreground so the dispute summary is on screen immediately) and the same answers sit in Detail once the check date arrives.
  Yes → `.verifiedStopped` + archive.
  No → `.stillCharging`, exactly one retrospective `.unexpectedCharge` row (this flow is the state's only producer), and a `DisputeSummary` - cancellation instant, evidence, charge date and amount - rendered readable-aloud with share and copy in Detail.
  Unanswered → `catchingUpOnUnansweredChecks` runs on every scheduling pass: each passed check date increments `unansweredCheckCount` and rolls the watch to the next would-be charge; at exactly 3 the record escalates to `.needsManualReview`, notifications stop, and the persistent Today card (already wired in Wave 4) is the escalation.
  One pass catches up an arbitrary absence, so nothing depends on when the app was opened.
- 251 tests: 122 domain + 54 persistence + 70 host-side services/stores + 5 on the simulator (Dynamic Type, plus dispute-summary and cancellation-screen render checks).

## Design decisions worth recording

- **One flow service, two callers.** "Both paths must produce identical state" is enforced structurally (shared implementation) and then still tested end-to-end, because a shared implementation can still be called with different arguments.
- **The record precedes the status flip.** `.cancellationPending` without a record is the §5.2b invariant violation (Failure B with extra steps); a record beside an active subscription is inert. Order chosen so every interruption point leaves the benign half and re-running heals it. Tested by priming the subscription save to fail.
- **The scheduler owns the roll-forward.** It already runs on every §6.2 trigger, including `BGAppRefreshTask`, and the catch-up is a pure domain function, so putting it in the pass keeps "derived from stored state plus today" true without adding a new lifecycle hook.
- **"Keeping it" acknowledges the earliest still-expected charge on or after today** - the charge every reminder kind (lead, day-of, catch-up, trial rungs) is about. Confirming a conversion instead targets the conversion row by date: acknowledging "the next upcoming" there would silence a renewal reminder the user never asked to silence (caught by a failing test during the wave).
- **`nextWouldBeChargeDate` keys off the trial term, not the status.** `billingAnchor(asOf:)` derives from the stored `.trial` status, which the cancellation flow has just overwritten - so a converted-but-unflipped trial cancelled after conversion would have been watched on the wrong sequence (see findings).
- **The dispute amount uses the anchor to date `amountCents`.** An unflipped trial's stored amount is the trial-era price, so charges on/after conversion cost `convertsToAmountCents`; a flipped subscription's anchor IS the conversion date and `amountCents` is current truth, surviving later manual price edits.
- **Answers are accepted from `.needsManualReview`** - the persistent card exists to be answered - and "Resolved - charges have stopped" is offered from `.stillCharging`, because disputes end.

## Deliberate limits (not bugs)

- The verification screens live inside Detail rather than as a separate modal; Today's cards navigate there. Spec §7.1 calls the prompt a screen; the question-plus-two-buttons shape did not earn a modal of its own.
- Cancelling a `.paused` subscription computes the check date from the anchor sequence, ignoring `pauseEndsOn` (underspecified; flagged in the report).
- `NotificationStatusStore.outcome` may lag one pass behind after a handler-path action (the handler reschedules directly); the next foreground pass reconciles it.
- The end-to-end compressed-timeline trial test on a device is the wave's ⛔ gate and needs the owner's hands; nothing here discharges it.
