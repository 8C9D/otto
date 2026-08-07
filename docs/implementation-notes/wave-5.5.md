# Wave 5.5 - baseline verification and hardening

Date: 2026-08-07

Not a feature wave.
This wave proves the committed baseline from a clean clone, lands the two field additions that must precede CloudKit, and installs standing guards for the two bug classes that have actually shipped.

## What exists after this wave

- **Spec v1.5** replaces v1.4 (`0657595`), folding in every Wave 5 finding: derive-before-you-mutate, the backwards materialization window, the stored dispute amount, the TrialTerm-is-history invariant, paused-cancellation semantics, `PriceChange.Source.trialConversion`, and the two notification categories.
- **`Subscription.lastMaterializedThrough`** (`800cd9e`), both layers: the §5.3 watermark.
  `expectedCharges` now takes the window and the as-of day separately - status derives as of today, the window reaches back to the watermark - and `materializeEvents` reads the watermark from the STORED record (a stale caller snapshot cannot reopen the window), advances it in the same save as the rows it vouches for, and treats a nil watermark as today-once (the pre-v1.5 migration, no stage needed).
  New entries start the watermark at the later of anchor and entry day, so Mode B never backfills history it had no rows for; edits never touch it.
  The founding-scenario test at the ledger layer exists: a conversion behind today on the FIRST pass still gets its row.
- **`CancellationRecord.expectedChargeAmountCents`** (`800cd9e`), both layers: computed once at cancellation from the pre-mutation subscription, rolled forward with the watch date, preferred by the dispute summary and the `.unexpectedCharge` row, with the old derivation demoted to a legacy-record fallback.
  The §5.4 roll-forward backfills nil amounts on pre-v1.5 records.
- **`scripts/verify.sh`** (`185fc3e`): clones the committed HEAD into a temp dir - deliberately not the working tree - then xcodegen, per-package `swift test`, app build, `swiftlint --strict`, and prints real per-package counts, failing loudly at each step.
  Documented in the README as the thing to run before reporting any wave complete.
- **CI** (`e82efe4`): jobs for OttoDomain, OttoPersistence, the OttoUI package (OttoStores + OttoServices + OttoUI on the mac host), a simulator job that runs the whole OttoUI package including the Dynamic Type suite (device resolved by UDID so an image change fails loudly instead of skipping), swiftlint --strict, the app build, and a verify.sh job.
  The `OttoUI-Package` scheme and simulator invocation were exercised locally; the ONLY unverified thing in the file is the `macos-26` runner label, commented as such at the top.
- **Ordering guards** (`194d905`): domain tests pinning that the cancellation derivations answer identically before and after the status overwrite (and that `billingAnchor` deliberately does NOT - the sharp edge documented, not hidden), plus a services suite that snapshots the world pre-flow and requires every derived-persisted value to equal a fresh derivation from the snapshot, for all three mutate-and-derive flows.
- **The phone-in-a-drawer standing harness** (`194d905`): one shared wake helper, four subsystem tests - status derivation, materialization, reminder planning, verification roll-forward - each asserting one wake equals timely daily passes.
  The file's contract: a new time-dependent subsystem gets a test there as part of landing, because none of the three historical escapes inherited the property.
- **`docs/manual-verification.md`** (`2867238`): the three outstanding device checks as numbered checklists with a pass criterion per step and a run log.

## verify.sh against this wave's HEAD

Passed clean: OttoDomain 129, OttoPersistence 59, OttoUI 82 - 270 on the mac host, plus 5 Dynamic Type tests that exist only on a simulator (verified locally via `xcodebuild test -scheme OttoUI-Package`), 275 total.

**The inherited "252 tests" figure was never reproducible by a host-side run.**
At `cb3486f` the host packages report 247 (122 + 54 + 71); 252 is only reachable by adding the 5 simulator-only tests.
Nothing was broken at HEAD - Wave 5's arithmetic was honest - but the counting method was never written down, which is how a figure becomes unfalsifiable.
verify.sh now prints what it can see and explicitly names what it cannot.

## Findings and deviations (in the report tradition: not polite)

1. **One SIGSEGV flake in OttoPersistence.** The first-ever verify.sh run died with signal 11 mid-suite in the clean clone; nine subsequent runs (working tree and fresh clones) all passed.
   Suspected SwiftData under swift-testing's parallel suites.
   Deliberately NOT masked with a retry; if it recurs in CI it stops being an anecdote and needs a real investigation.
2. **Spec v1.5 §5.4 paused-cancellation is specified but not implemented.**
   `startCancellation` still computes the check date from the anchor sequence, ignoring `pauseEndsOn`; the defer-and-ask path needs UI, which this wave forbids.
   Wave 6 must reconcile code to spec here - it is the one place v1.5 and the code now knowingly disagree.
3. **The watermark advances during a pause, so a late resume cannot backfill.**
   Charges between `pauseEndsOn` and a late manual resume fall behind an already-advanced watermark and never materialize.
   v1.5 does not address it (pause "expects nothing" is evaluated as of today across the whole backward window); needs a spec decision before it can be code.
4. **The watermark write does not bump `updatedAt`** - it is scheduler bookkeeping, not a user edit, and bumping would make every daily pass look like an edit.
   Under CloudKit that leaves the watermark's merge behavior undefined; a regressed watermark is safe (dedup absorbs re-observation) but wasteful.
   Wave 6 must decide the sync merge policy for it explicitly.
5. **`expectedChargeAmountCents` is `Int?` in the domain where the spec table says `Int`.**
   Nil means "recorded before v1.5"; there is no honest non-optional default for a record whose amount was never captured, so the type says so, the roll-forward backfills, and the display falls back to the old derivation only for those records.
6. **Schema fields were added to `OttoSchemaV1` in place**, not via a V2: additive optional properties are lightweight-migratable and the store predates any release.
   This is exactly the free pass that expires when Wave 6 turns on CloudKit - the next schema change after that uses the V2 machinery scaffolded in `OttoMigrationPlan`.
7. **"OttoServices" is a target, not a package** - the CI requirement "jobs for every package including OttoServices" maps to the OttoUI package job, which runs OttoServicesTests; the job name says so.

## Still on the owner (unchanged by this wave, procedures now written)

1. The compressed-timeline trial test on a device - the ⛔ Wave 5 gate, still not met.
2. The `BGAppRefreshTask` LLDB observation.
3. The hands-on add-a-subscription pass.
4. Adding the GitHub remote and pushing, which turns the CI file from prose into a process.
5. The Wave 6 decision: Android or paid distribution within ~12 months means a real backend instead of CloudKit; answer it before running Wave 6.
