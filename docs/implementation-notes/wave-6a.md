# Wave 6A - Watermark relocation and v1.9 reconciliation (CloudKit stays OFF)

Date: 2026-08-07

Wave 6 split: 6A converts "the watermark moved first" from a plan depending on a future wave's discipline into a committed, verified state, and reconciles the code with spec v1.9's schema resolutions while a schema change is still cheap.
CloudKit is not enabled; no entitlement, container setting, or `cloudKitDatabase` value changed.
The product of this wave is a verified state plus `docs/cloudkit-readiness.md`.

## What exists after this wave

- **Spec v1.9** replaces v1.8, committed alone - the schema is frozen at the end of this wave.
- **Schema V3 and the V2→V3 migration.**
  `OttoSchemaV2` is now a frozen legacy declaration (the migration source); V3 drops `lastMaterializedThrough` from `StoredSubscription`, drops `evidenceNote` from `StoredCancellationEpisode`, and adds the one-to-many `StoredEvidenceNote` table.
- **The device-state store (spec §5.3).**
  A second, LOCAL-ONLY store (`OttoDeviceState.store`) in its own `ModelContainer`, holding `StoredMaterializationWatermark` (one row per subscription).
  It is deliberately its own container, not a second configuration of the main one: SwiftData's staged migration refuses any container whose schema is not exactly one of the plan's versions (probed empirically - "Cannot use staged migration with an unknown model version"), and a separate container also makes it structurally impossible for a future configuration change to sweep device state into the synced schema.
  The store is named for its purpose - device-scoped bookkeeping generally, not the watermark specifically - so settings or future device state have a home without a second relocation.
- **The carry-over is durable and asserted, not assumed.**
  The V2→V3 stage's `willMigrate` writes every watermark into the device-state store and VERIFIES the readback while the V2 column still exists; any failure aborts the migration with the store still at V2, and the upsert makes retry idempotent.
  There is no window in which the values exist nowhere, and a V2 store with watermarks refuses to migrate at all if no device-state destination was provided (`MigrationError.deviceStateStoreUnavailable`) - dropping them silently is the one outcome the design forbids.
- **Two-store writes are ordered by hazard direction (spec §5.3).**
  One atomic save across two files does not exist, so every method that writes both orders its saves so a crash lands on the safe side: materialization advances rows-first (a crash leaves rows without an advanced watermark - re-observed idempotently); edits rewind watermark-first (no flow advances a watermark through `save()`, so the crash side is a regressed watermark - harmless).
  `restore()` syncs device rows after the main save so a refused import leaves device state untouched; the small crash window there is documented in the readiness audit.
- **The §5.4 v1.9 folding: `.verifiedStopped` left `verificationState`.**
  Verification passing no longer sets a state - it closes the episode with `outcome = .verifiedStopped`.
  `reminderSchedule` and `disputeSummary` now key off openness (the checks the removed state used to carry); TodayOverview treats the verified OUTCOME as resolved.
  Stored rows, v1/v2 export files, and any pre-fold record that might ever arrive all upgrade by one shared rule (`CancellationEpisode.legacyClosure` + park the vestigial live state at `.pending`), applied in the migration, the persistence mapping, and the wire format so the paths cannot drift.
- **`evidenceNote` became `evidenceNotes` (spec §5.4 v1.9): one row per dispute artifact.**
  `EvidenceNote` carries the §5.0 quartet; the single legacy string upgrades to one note with a DERIVED id (`EvidenceNote.legacyNote`, mask "EvidNote" - re-import and re-migration cannot duplicate it) and timestamps borrowed from the episode.
  Export format v3 under v1.8's any-field-change-bumps policy; v1 and v2 files decode forever.
  The flows grew the minimal surface the list implies: append, edit-in-place, and clear-tombstones (spec §3.5 - removal is a soft delete); the dispute summary reads each note with its own date.
- **`docs/cloudkit-readiness.md`** - the report-only audit gating 6B, with its pre-6B work list.

## Decisions worth recording

- **The migration refuses rather than degrades.** A V2 store with watermarks and nowhere to put them fails to open; wasteful-but-safe was rejected because a lost watermark is NOT safe in current code - a nil watermark materializes from `today`, skipping the unobserved window (the founding hazard), not from the anchor.
- **Vestigial live state on closed episodes is `.pending`.** The true last live state of a pre-fold verified episode is unrecoverable; `.pending` is the neutral honest default, and nothing reads the state once an episode is closed.
- **`CloudKitCompatibilityTests` was still asserting V2** and green; it now asserts V3 plus a nothing-device-scoped check. Version-pinned checks need tripwires - see the audit's Question 1.

## Test-infrastructure note

The persistence target now declares THREE schema versions sharing entity names; the existing serialized root (Wave 8.5's fix for the name-keyed registry race) covers the new V2→V3 suites unchanged.
Migration tests inspect the migrated store FILES with raw SQLite (tables, columns, values), not just the mapped domain values - a claim about the artifact is not the artifact.

## verify.sh against this wave's HEAD

See the wave report; run from a clean clone per the script's contract.

## Where the next wave starts

Wave 6B (CloudKit enablement) is gated on the four manual checks (compressed-timeline trial test, `BGAppRefreshTask` observation, hands-on add pass, manual export inspection) and on the readiness audit's pre-6B list - above all the embedded-array save redesign (absence must stop meaning removal) and the rollback machinery (pre-enable snapshot, kill switch, zone purge).
