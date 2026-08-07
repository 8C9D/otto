# Schema-freeze review - Wave 8.5

**Purpose:** the written sweep spec v1.8 §5.3a calls for, answering the six Wave 8.5 questions against every model, relationship, and enum in spec §5.
This document gates Wave 6: after CloudKit turns on, relationship cardinality and the meaning of existing fields become effectively permanent, so every "leave it" verdict below is a decision to live with the shape forever.
Everything was reviewed against the code at this commit (schema `OttoSchemaV2`), not against the spec's prose alone.

**The schema being frozen (V2):**

| Model | Relationships |
|---|---|
| `StoredSubscription` | `trial` (to-one `StoredTrialTerm`), `billingEvents` (to-many), `cancellationEpisodes` (to-many, new), `pauseEpisodes` (to-many, new), `priceChanges` (to-many), `paymentMethodID` (scalar to-one reference) |
| `StoredTrialTerm` | child of subscription |
| `StoredBillingEvent` | child of subscription, plus scalar `subscriptionID` |
| `StoredCancellationEpisode` | child of subscription, plus scalar `subscriptionID`; replaces V1's one-to-one `StoredCancellationRecord` |
| `StoredPauseEpisode` | child of subscription; replaces V1's `pausedOn`/`pauseEndsOn` field pair |
| `StoredPriceChange` | child of subscription, plus scalar `subscriptionID` |
| `StoredPaymentMethod` | standalone; subscriptions point at it by scalar id |

---

## Question 1 - which to-one relationships model something that can happen more than once?

The two Wave 8 found are fixed this wave: cancellations and pauses are now one-to-many episode tables, closed with end dates, never cleared.
The sweep looked for siblings, including the four the prompt named.

| Relationship | Recurs? | Verdict |
|---|---|---|
| `Subscription.trial` (to-one) | Theoretically - a vendor can re-offer a trial | **Leave to-one, meaning pinned.** See write-up below |
| `Subscription.paymentMethodID` (to-one reference) | Yes - subscriptions move between cards | **Leave, deliberately.** See write-up below |
| `Subscription.category` (to-one to a fixed enum) | Yes - the user can recategorize | **Leave.** Same reasoning as payment method |
| `Subscription.cancellationURL` / `cancellationNotes` | n/a | **Correct at subscription level.** They describe how to cancel the vendor, not any one cancellation, so they deliberately do not move onto the episode |
| `BillingEvent`, `PriceChange` | Already one-to-many | **Correct** |
| `CancellationEpisode`, `PauseEpisode` | Now one-to-many | **Fixed this wave** |

**The distinction that decided the "leave" verdicts.**
The change class that is impossible after Wave 6 is converting an existing to-one into a to-many, because that changes what existing rows and fields mean.
Adding a brand-new table beside an untouched field is additive and stays cheap forever.
So the test applied was not "could this recur?" but "if it recurs, does the CURRENT field's meaning have to change?"

**`trial` - leave to-one, with its meaning pinned now.**
`trial` records how this subscription BEGAN, and §5.2b already treats it as history on a non-`.trial` record: never rebuilt, never deleted by an edit, retained through conversion.
A re-offered trial is a new beginning, and the honest model for it is a new subscription record (the old one archived), not a second term on the same row - the anchor, price history, and ledger of the old lifetime would all be wrong for the new one anyway.
If that ever proves inadequate, a `TrialEpisode` table can be added additively while `trial` keeps meaning "the founding term".
The regret risk is judged low because the meaning is pinned in writing here, before any data exists that could contradict it.

**`paymentMethodID` - leave, and the loss is real but chosen.**
When the user moves a subscription to a new card, the old assignment is overwritten and unrecoverable - the same unrecoverability class as the pre-v1.5 cancellation amount.
It stays anyway, for three reasons: no shipped or specified feature reads historical card assignment (the dispute summary and §7.4's per-card load both want the current card); a `PaymentMethodAssignment` history table is a purely additive later change if a feature ever wants one; and unlike `expectedChargeAmountCents`, nothing derived from it is presented as a fact to a bank.
This is the one Question-1 verdict that discards information, so it is stated rather than implied.

**`category` - leave.** Identical structure to payment method, lower stakes: rollups only ever want the current category.

## Question 2 - which fields are cleared or overwritten on a state exit, rather than written to history?

The rule since v1.8: nothing is cleared on exit from a state; exiting writes an end date.

| Site | Behaviour | Verdict |
|---|---|---|
| Pause exit (`resuming`) | Was the bug - cleared both fields. Now closes the open `PauseEpisode` with `endedOn` and `.resumed` | **Fixed this wave** |
| Cancellation exit (un-cancel) | Did not exist. Now closes the episode with `.abandoned`; verification passing closes it with `.verifiedStopped` | **Fixed this wave** |
| Archive while paused | Leaves the pause episode OPEN, deliberately: billing never resumed, and a fabricated end date would be fiction. The subscription died paused and the data says so | **Correct, decided this wave** |
| Trial conversion (`confirmingConversion`) | Overwrites `amountCents` and rebases `cycleStartDay`, but the origin survives in full: the term keeps the trial anchor and price, and the transition is appended to `PriceChange` | **Correct since v1.5** |
| `evidenceNote` clearing | `updateCancellationEvidence` replaces or clears on request | **Correct - a user editing their own note is not a state exit** |
| Watermark writes | Overwritten by ledger passes and rewinds | **Correct - device bookkeeping, not history (spec §5.3)** |

No remaining site clears state on exit.
The one new near-relative found: an import merge can close a losing open cancellation episode as `.superseded` - recorded as what happened, counted in the import summary, never deleted.

## Question 3 - which enums are likely to gain cases, and which cases do double duty?

All wire enums use stable raw strings (spec §5.6), so ADDING cases is and stays cheap.
The freeze risk is a case whose current meaning is vague enough that someone later narrows or splits it.

| Enum | Verdict |
|---|---|
| `SubscriptionStatus` | ⚠ **`.cancelled` is a case no flow has ever produced** - see write-up |
| `BillingEvent.State` | **Clean.** `.confirmedNotCharged` (asked, no charge) and `.skipped` (deliberately waived, e.g. a free month) are adjacent but documented as distinct; `.unexpectedCharge` has exactly one producer by spec. A future `.refunded` would be a cheap addition |
| `CancellationEpisode.VerificationState` | **Clean.** Five cases, each with one producer and one meaning |
| `CancellationEpisode.Outcome` (new) | **Clean by construction:** `.verifiedStopped`, `.abandoned`, `.superseded` - one producer each |
| `PauseEpisode.Outcome` (new) | **One case (`.resumed`) today.** Deliberate: resume is the only exit that exists, and inventing outcomes for exits that cannot happen would be double duty from day one |
| `PriceChange.Source` | **Clean** - three cases, three producers |
| `Category` | **Clean** - fixed list, additive by design, `Other` as the escape valve |
| `BillingCycle.Unit` | **Complete** - day/week/month/year spans the domain |

**`.cancelled` - the one flag.**
Every transition path goes `.cancellationPending` → `.archived`; nothing ever writes `.cancelled`, yet the UI filters on it, badges it, and every switch handles it.
Because no flow has ever produced it, no stored or exported data can carry it, which means its meaning can still be assigned safely - once, now, in writing:
if a future wave ever splits "cancellation performed and confirmed with the vendor" from "user says they are cancelling", `.cancelled` takes the former meaning, which every existing switch already renders sensibly (it is grouped with `.cancellationPending` everywhere).
It is NOT removed, because deleting a wire-format case the week before the format freezes buys nothing and costs a v3.
Verdict: keep, meaning reserved as stated here.

## Question 4 - which fields are non-optional but have no honest default for a record created before they existed?

The `expectedChargeAmountCents` class.
Swept every field against the data that migration and the v1 import actually produce.

| Field | Verdict |
|---|---|
| `PauseEpisode.startedOn` | **Made optional this wave** - a pause migrated from a pre-Wave-7 record has no recorded start, and nil is the honest value; Insights falls back to the current price, as it already did |
| `CancellationEpisode.statusAtStart` | **Optional by design** - v1 never captured what a cancellation interrupted; the un-cancel restore derives the best honest answer for nil (open pause episode → `.paused`, live term → `.trial`, else `.active`) and the derivation converges even when it guesses a confirmed conversion back to `.trial` |
| `CancellationEpisode.endedAt`/`outcome` | **Optional-as-open** - nil IS the open state, enforced paired |
| `unansweredCheckCount` | Non-optional with default 0 - honest: "never rolled forward" |
| `expectedChargeAmountCents` | Already optional since v1.6; nil means "pre-v1.5 record", backfilled by the roll-forward |
| `currencyCode`, `reminderLeadDays`, `sameDayReminder` | Non-optional with true domain defaults that exist for every record ever created |
| Everything else | Present since each model's first row, or optional |

No violations remain.

## Question 5 - what is stored that is derivable, and what is derived that should be stored?

**Stored-when-derivable (the anchorDay class - redundant state that can disagree):**

| Item | Verdict |
|---|---|
| `pausedOn` / `pauseEndsOn` | **Fixed this wave** - they were about to become exactly this class (fields duplicating the open episode); both are now derived accessors onto `currentPauseEpisode`, so they cannot disagree with it |
| `anchorDay`/`anchorMonth` | Already derived (v1.1) - **correct** |
| `TrialTerm.conversionDate`/`cancelByDate` | Computed - **correct** |
| Scalar `subscriptionID` beside the relationship (billing events, cancellation episodes, price changes) | **Deliberate, kept** - the Wave 2 decision record: the relationship cascades, the scalar keeps predicates plain and survives a partially synced parent. `PauseEpisode` deliberately has no scalar, following the trial precedent, because nothing ever fetches pauses except through their subscription |
| `CancellationEpisode.verificationState` vs `outcome` | **Partial overlap, kept** - a `.verifiedStopped` state always travels with a `.verifiedStopped` outcome, but the outcome is not derivable in general (`.abandoned` and `.superseded` close an episode whose state still says what the watch was doing). The state is the watch machine, the outcome is why watching ended; the one overlapping pair is written by a single flow |

**Derived-when-it-should-be-stored (the expectedChargeAmountCents class - unrecoverable later):**

| Item | Verdict |
|---|---|
| Check date and amount at cancellation | Stored at cancellation since v1.1/v1.5 - **correct** |
| Pause freeze point | Stored on the episode - **correct** |
| Status the cancellation interrupted | **Stored this wave** (`statusAtStart`) - the trial-versus-confirmed-conversion ambiguity cannot be derived back honestly, and the previous design's answer ("there is no un-cancel") was the Wave 8 finding |
| Historical payment-method assignment | **Knowingly not stored** - Question 1's write-up |

## Question 6 - anything device-local still living in the synced schema?

| Item | Status |
|---|---|
| The materialization watermark (`lastMaterializedThrough`) | **Still physically on `StoredSubscription`, knowingly.** Spec v1.7 already pins the fix as Wave 6's FIRST schema act: a second local-only `ModelConfiguration`, moved before any data exists in CloudKit. Moving it this wave was considered and rejected - it would change the store layout twice in two waves for no additional safety, since nothing syncs until Wave 6 |
| Settings | **Already outside the schema** - `UserDefaults` via `SettingsStore`, and excluded from the export per v1.8 §3.5 |
| The third thing | **Searched; found a soft one.** `unansweredCheckCount` is user data, not device state - but its MERGE behaviour is device-shaped: two devices each rolling the same unanswered watch forward will each count the same missed cycles, and last-write-wins between them is fine (they converge on the same count) UNTIL the two devices disagree about `today`. This is not a schema problem and needs no field moved; it is recorded here so Wave 6's merge review checks it deliberately rather than discovering it |

Nothing else in the schema describes "this device's progress" rather than "the user's data".

---

## Fixed this wave

- `CancellationEpisode` and `PauseEpisode` one-to-many tables, both layers, with the §5.0 quartet, migration from the V1 shapes, and the v1-export upgrade path sharing one rule with the SwiftData migration.
- Un-cancel (`abandonCancellation`): closes the open episode `.abandoned`, restores `statusAtStart`, heals if killed between its two writes, and rewinds the watermark behind the watched date for migrated data.
- The watermark now freezes during `.cancellationPending`/`.cancelled` (same mechanism as the indefinite pause), so an un-cancel backfills every charge date the watch covered.
- Invalidation never touches rows dated today or earlier (spec §5.3 v1.8); a passed-unconfirmed charge stays in the ledger through any price or schedule edit.
- Export format v2 with the any-field-change-bumps policy; v1 files import with documented defaults, deterministically (the synthesized pause episode's id is derived from the subscription id, so re-import cannot duplicate it).

## Decided against, with reasons

- Payment-method and category history tables: additive later, no current consumer, meaning of the current fields unchanged by their absence (Question 1).
- Trial episodes: a re-offered trial is a new subscription lifetime; `trial` means the founding term, pinned above (Question 1).
- Removing `SubscriptionStatus.cancelled`: meaning reserved in writing instead (Question 3).
- Closing pause episodes at archive: an archived-while-paused subscription genuinely never resumed, so its episode stays open (Question 2).
- Moving the watermark out of the schema this wave: stays Wave 6's first act, per v1.7 (Question 6).

## Genuinely ambiguous - written up, not guessed

1. **Merge granularity for pause episodes before Wave 6.**
Pause episodes are embedded in their subscription (like the trial), so a pre-CloudKit import merge resolves them WHOLESALE by the subscription's `updatedAt` - a device that renamed the subscription yesterday beats a device that paused it this morning, and the pause episode from the losing side is silently absent from the merged subscription.
This is exactly how the v1.7 pause FIELDS already merged, so nothing regressed, and under CloudKit (per-record sync) episodes become individually merged rows and the problem dissolves.
But if the owner expects export/import merge between two actively-used devices to be a primary workflow BEFORE Wave 6, this is the sharpest known edge, and the alternative (top-level pause array in the export with its own merge, like cancellation episodes) is still cheap for one more wave.
2. **`evidenceNote` is one field, not a log.**
A long cancellation fight produces multiple confirmation numbers and reps; today they share one free-text field the user edits in place.
An `EvidenceEntry` table would be additive later; flagged because the dispute summary is the app's most external artifact.

## What I would regret freezing, ranked

1. **The watermark still living on `StoredSubscription` when Wave 6 opens.**
Everything depends on Wave 6's "first schema act" actually being first; if CloudKit is ever enabled with the watermark still in the synced schema, spec §5.3's advanced-watermark hazard (device B skipping charges device A vouched for) becomes real user-facing loss.
It is the one deferred item with a failure mode this project exists to prevent, which is why it is restated here rather than trusted to memory.
2. **`statusAtStart` as a stored copy of a `SubscriptionStatus`.**
It is the only place a status value is stored OUTSIDE the subscription's own column, so any future change to status semantics has a second site to consider.
The alternative (deriving the restore) was rejected for containing a genuine heuristic, and the field is optional with a documented nil - but it is the newest idea in the schema and has had the least time to be wrong.
3. **The unarticulated one, said out loud as instructed:** the pair `verificationState` + `outcome` on `CancellationEpisode` feels one field too wide, and I cannot fully articulate why - the invariants pin every combination the flows can produce, the tests cover them, and no concrete failure is visible.
If a cheap simplification exists it would be folding the terminal states into one machine, and that is precisely the kind of meaning-narrowing change that must happen before Wave 6 or never.
It is flagged for one deliberate look while a change is still a migration away, not a support incident.
