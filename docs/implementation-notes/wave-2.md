# Wave 2 - persistence

Date: 2026-08-06

## What exists after this wave

- The spec v1.1 reconciliation in the domain: `CancellationRecord.expectedFinalChargeDate` renamed to `nextChargeDateIfNotCancelled` and made non-optional, and `Subscription.sameDayReminder: Bool` added (default false).
  The verification planner now fires on the stored check date as-is; once that date has passed unverified, it keeps watching the first would-be charge date on or after today.
- A second package, `Packages/OttoPersistence`, holding spec §3.4 layers 3 and 2 as separate targets so the compiler enforces the layering: `OttoRepositories` (protocols: `SubscriptionRepository`, `BillingEventRepository`, `CancellationRepository`, `PriceChangeRepository`, `PaymentMethodRepository`) depends only on OttoDomain; `OttoPersistence` implements them with SwiftData.
- Six `@Model` persistence records (`StoredSubscription`, `StoredTrialTerm`, `StoredBillingEvent`, `StoredCancellationRecord`, `StoredPriceChange`, `StoredPaymentMethod`) nested in a versioned `OttoSchemaV1`, plus an `OttoMigrationPlan` scaffold so migration machinery predates the CloudKit constraint.
- A mapping layer in both directions with explicit, typed error handling (`MappingError`), and the storage shapes from the decision record: calendar days as single yyyymmdd Ints, billing cycles as two scalar columns, enums as stable raw strings, money as integer cents.
- `OttoStore`, a `@ModelActor` actor implementing all five repository protocols over one serialized context, and `OttoContainerFactory` producing the on-disk and in-memory containers - both with `cloudKitDatabase: .none`, the line that keeps CloudKit off until Wave 6.
- `BillingEvent` materialization per spec §5.3: rows created inside the horizon window, idempotently, deduplicated by `(subscriptionID, expectedDate)` against all existing rows including tombstones.
- 41 tests in 6 suites: round-trips for every model, storage-shape edge dates (Feb 29, Dec 31, yyyymmdd boundaries), soft-delete filtering and cascade, mapping-failure paths, materialization, and the CloudKit-compatibility schema assertion.
- The domain suite is at 51 tests in 11 suites after the reconciliation.

## Design decisions worth recording

- The `@Model` classes are internal to the package, so "nothing above layer 2 ever sees a persistence type" is compiler-enforced rather than convention.
- Mapping failure policy, applied consistently: the mapping layer always throws; repository reads catch per record and skip it with an error log, because a partially synced record is - in domain terms - not there yet, and one bad row must not take down a list read; writes never map from records, so their failures always surface.
  A subscription whose trial record is unmappable is skipped whole rather than returned half-loaded.
- Required-by-domain fields are stored optional and their absence is a mapping error; only fields with a true domain default (`sameDayReminder`, `isDefault`) carry a storage default, so a partial record can never silently invent data.
- Child records store a scalar `subscriptionID` beside the relationship: the relationship is the structural link that cascades, the scalar is the domain identity that survives a partially synced parent and keeps predicates plain; the store writes both together.
- Soft delete is the repository default, opt-out by method name (`...IncludingDeleted`); `deleteSubscription` cascades the tombstone to trial, billing events, cancellation record, and price changes, never overwriting an earlier tombstone's instant; hard deletes happen nowhere.
- No method in the store reads a clock; every instant is a parameter or a field of the value being saved (a trial removed on save is tombstoned at the subscription's `updatedAt`).
- Materialization only runs for `.active`: paused explicitly generates no rows (spec §5.1), a trial has no charges before conversion, and cancellation states are watched by verification rather than expectation.
  The window includes today itself, and every candidate date is computed directly from the anchor by the date engine, never by iterating from a computed date.
- The one-to-one trial and cancellation slots reuse their existing record on save, clearing any tombstone, because the slot can only hold one record and resurrection is the only coherent semantics.
- The CloudKit-compatibility test was mutation-verified: a unique `id` and a required-no-default property were temporarily added to a model and the test failed on both, then the model was restored.

## Note for Wave 3

- There is no `@Query` anywhere in this project, and there must never be: it only works inside SwiftUI views and would wire the UI straight to SwiftData.
  Repositories expose async pull-based reads returning domain values, so Wave 3 must build an observable store layer (`@Observable`, refreshed after writes) to get view updates - they do not come free.

## Deliberate limits (not bugs)

- `BillingEventRepository` has no per-event delete; a billing event only dies through its subscription's cascade, because no product flow deletes a single expected charge.
- List reads sort deterministically (name/date, then id) after mapping, in memory; row counts are small and UI-facing ordering is a Wave 3 concern.
- Repository reads log-and-skip unmappable records; nothing yet surfaces "N records were skipped" to a health UI, which may be worth revisiting at Wave 6 when partial records become real.
