# Wave 3 - core UI

Date: 2026-08-07

## What exists after this wave

- The spec v1.2 reconciliation, before any UI:
  - The audit quartet (`id`, `createdAt`, `updatedAt`, `deletedAt`) on every model in both layers (spec §5.0): added to `TrialTerm`, `CancellationRecord`, `BillingEvent`, `PriceChange`, and `PaymentMethod`, in the domain structs, the stored records, and the mappings.
  - `.trial` materializes exactly one billing event, at `conversionDate`, for `convertsToAmountCents` (spec §5.3).
  - The materialization window is the reminder window: `materializeEvents` now takes `maxReminderLeadDays` explicitly and materializes through `today + horizonDays + maxReminderLeadDays`, so Wave 4 cannot forget the widening.
  It also takes `at instant: Date` for the new rows' audit fields, keeping the store clock-free.
- Two additive domain calculations the UI needs (Wave 3 constraint 2):
  - `todayOverview` / `todayEntry` - the Today screen's three-section classification as a pure function, also reused for the subscription list's next-date column so the two cannot disagree.
  - `lastDayOfMonthAnchor(forNextBillingDate:cycle:)` - the arithmetic behind §5.1's Mode B disambiguation: the month-end anchor that would land on the entered date by clamping, or nil when the date is unambiguous and no question should be asked.
    It walks earlier cycle months, so quarterly Feb 28 correctly anchors the previous Aug 31 and annual Feb 28 anchors the nearest earlier Feb 29.
- A third package, `Packages/OttoUI`, holding spec §3.4 layer 5 in two targets:
  - `OttoStores`: the observable store layer - `SubscriptionsStore`, `SubscriptionDetailStore`, `PaymentMethodsStore`, `SubscriptionFormModel`, `SubscriptionListModel`, `AppModel`, plus `LoadState`, `DateProvider`, and the display formatters.
    `@MainActor @Observable` classes holding domain values, loaded through the repository protocols, with loading and error explicit (`LoadState`: `.loading` / `.loaded` / `.failed` - an empty list is `.loaded([])`, never a stand-in, and a repository error is `.failed`, never an empty list).
    Mutations go through the stores, which write via the repository and refresh their published state; a failed write throws to the caller and leaves published state untouched.
  - `OttoUI`: the four screens - Today, Subscriptions, Add/Edit, Detail - plus previews against fixture repositories covering the awkward cases (31-anchored, trial two days from conversion, paused, no payment method).
- Neither target declares a dependency on `OttoPersistence`, so `import OttoPersistence` anywhere in the UI is a compile error - verified by adding the import and watching the build fail.
  The app target is the composition root: the only place that names `OttoStore` and `OttoContainerFactory`, and it hands `AppModel` (repositories as protocols) to the view tree.
  Container-creation failure is carried as a `Result` and rendered, not crashed on.
- `DateProvider` is the single boundary where "now" enters: the domain takes days and instants as parameters, the persistence store takes every instant as an argument, and the stores inject a `.live` or fixed provider.
- Add/Edit per §5.1: both entry modes in one segmented control, Mode B's last-day question rendered inline only when `lastDayOfMonthAnchor` says the date is ambiguous, and cleared automatically when the date, cycle, or mode changes.
  Mode A shows the computed next billing date live; the trial block shows conversion and cancel-by dates live.
  The price field is a locale-aware currency `TextField` bound to `Decimal`; cents are derived by decimal rounding, never re-parsed from a string.
- Accessibility from the first view: no fixed heights anywhere, rows combined into single VoiceOver elements with spoken labels for currency/date/status meaning, status always symbol + text (colour only reinforces), and money and dates rendered exclusively through Foundation formatters.
- 156 tests: 69 domain + 46 persistence + 38 store/view-model (all host-side via `swift test`) + 3 Dynamic Type tests that run UIKit-hosted on the simulator (`xcodebuild test -scheme OttoUI-Package`), rendering the list row, every Today card, and the ledger row at AX5 and asserting the layout grows rather than clamps.

## Design decisions worth recording

- The one-to-one trial and cancellation slots now write the domain value's own tombstone verbatim instead of clearing it as a side effect; resurrection still works because a live domain value carries `deletedAt == nil`.
- A `.trial` subscription with no trial term materializes nothing and produces no Today entry, matching the reminder planner's treatment of the same state (see "wrong or underspecified" in the report - the state itself is the problem).
- A trial's materialized conversion charge only exists when `conversionDate >= today`; §5.3's window starts at today, so a conversion already in the past (status still `.trial`) gets no row until Wave 5 defines the transition.
- The Today classification interprets §7.1 as follows, pinned here because the spec doesn't say:
  - A trial is "inside its cancel-by window" from `cancelByDate - reminderLeadDays` through `conversionDate`; past conversion while still `.trial` it stays in Needs action rather than vanishing.
  - A pending verification is in Needs action once its check date has arrived (`<= today`); with a future check date it is an upcoming item.
    §5.4's roll-forward and three-cycle cap govern notifications (Wave 5), not this section - the card is already persistent.
  - A cancelled subscription with no cancellation record surfaces in Needs action dated today, rather than being silently unwatched.
- Editing prefills Mode A with the stored anchor, because the anchor is the fact on record; a save constructs a new `Subscription` value, so the anchor is correctable on edit while `cycleStartDay` stays a `let` against in-place mutation.
- The form preserves lifecycle statuses it does not own: the trial toggle moves a subscription only between `.trial` and `.active`; paused/cancelling/cancelled/archived pass through untouched.
- For a trial, the single price field is both `amountCents` and `convertsToAmountCents` - one number entered once; they diverge later only if Wave 5's flows decide they should.
- The trial toggle swaps the lead-days default (3 renewals / 5 trials, spec §10) only while the field still holds the default it is leaving, so a user-chosen value never changes under them.
- `SubscriptionListModel` sorts cost descending (the "what is costing me?" order), dates ascending with dateless rows last, and always tie-breaks by id so ordering is deterministic.
- Wave 5-7 surfaces are stubbed, not built: Detail shows a disabled "Mark as cancelling…" entry point with a footer saying the flow comes later; the payment-method picker appears only if methods already exist (management is Wave 7); price history is a plain list (the chart is Wave 7).

## Deliberate limits (not bugs)

- Nothing calls `materializeEvents` yet: rows appear in a Detail ledger only if something else created them, because materialization is specified to happen at reminder-scheduling time and the scheduler is Wave 4.
- No notification code, no CloudKit, no Insights, no cancellation/verification flows, per the wave boundary.
- The Dynamic Type tests assert growth (AX5 well beyond default height), which catches fixed-height clamping - the mechanism behind truncation - but is not a pixel-level truncation proof; snapshot baselines would be the Wave 8 upgrade if wanted.
- `LoadState.failed` keeps the raw `Error` for the UI to describe; there is no retry policy beyond the user-visible Try Again.
