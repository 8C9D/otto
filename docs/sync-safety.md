# Sync safety - Wave 6B-Prep

**Scope:** the §4a mechanisms built before CloudKit can be enabled.
CloudKit was OFF for every change described here; nothing in this document turns it on.
Companion to `cloudkit-readiness.md` (the audit that motivated this wave) and spec v2.0 §4a, §5.3, §8.

## The invariant audit (spec §4a principle 2)

Every invariant reachable from two devices, with the three §4a answers: what write-time enforcement prevents it locally, what a sync-produced violation looks like, and how reading repairs it deterministically.

| Invariant | Write-time enforcement | Sync-produced violation | Read behaviour |
|---|---|---|---|
| At most one open pause episode (§5.3a) | `Subscription.init` precondition; every pause flow closes-then-opens in one value | Both devices pause independently: two open episodes, different ids | **Repaired**: earliest `startedOn` wins (ties: `createdAt`, then id); later episodes closed at the winner's start with outcome `.superseded`. Lossy → reported |
| No open episode beside stored `.active`/`.trial` (§5.3a) | Same precondition; resume closes the episode in the same value that flips the status | A resume on one device races a pause on the other; the status field converges by last-writer-wins while the episode record stays open | **Repaired**: the parent's status field is authoritative (it is the single field both devices converge on); the open episode closes at its own start as `.superseded`. Lossy → reported |
| `.paused` must have an open episode (§5.3a) | Same precondition; pausing writes both in one value | The parent record arrives before its episode child, or the other device's episode closure lands while status LWW keeps `.paused` | **Held**: reads as an indefinite pause - bills nothing, derives no resume, freezes the watermark. Nothing is invented; self-heals when the episode arrives. Reported |
| `.trial` must have a trial term (§5.2b) | Same precondition; the form refuses to build a trial without a term | The parent arrives before its trial child | **Held**: reads as a trial that never reaches conversion - no reminder, no materialized charge, no invented amounts. Self-heals when the term arrives. Reported |
| Pause episode open-or-closed, never half (§5.3a) | `PauseEpisode.init` precondition | Not producible by field-level merge of two valid records writing `endedOn`+`outcome` together; a half-set pair is field damage, not a sync artifact | **Refused** (record skipped, counted in `unreadableSubscriptionCount`): there is no honest repair for half a closure |
| Cancellation episode open-or-closed, never half (§5.4) | `CancellationEpisode` construction; the fold writes closure as one unit | Same as above | **Refused**, same reasoning |
| At most one open cancellation episode per subscription (§5.3a) | Flows reuse the open episode (`startCancellation` checks first) | Both devices cancel independently: two open episodes | **No read repair needed** - episodes are fetched, not embedded, so nothing becomes unreadable; `openEpisode` deterministically returns the newest. Converged durably by the reconciliation pass (below), which closes the older as `.superseded` - the import merge's existing rule |
| Ledger uniqueness on (subscriptionID, expectedDate) (§5.3) | `materializeEvents` dedups against locally visible rows | Both devices materialize the same charge date before the other's row arrives: permanent duplicate rows with independent acknowledgement state | **No read repair** (each row is individually valid); converged by the reconciliation pass (below) |
| Single default payment method | Store normalizes on save | Two devices each set a different default | Read picks deterministically; import merge already normalizes (newest default wins). Sync reconciliation: same rule, applied by the reconciliation pass when it runs |
| Status-coupled invariants apply to LIVE records only (v1.9) | Delete cascade tombstones children with the parent | - | Upheld by the repair path: a tombstoned subscription's episodes are history and no status-coupled repair touches them |

Two deliberate boundaries:

- **Field-level damage still refuses.** A missing required column or unknown enum string has no honest repair; the record is skipped, logged, and counted (`unreadableSubscriptionCount`), exactly as before. Repairs are only for shapes two CORRECT devices can produce between them.
- **Wire reads repair; wire writes still validate.** The export/import format and `Codable` apply the same repairing read, because a device that read-repaired but never re-saved exports the RAW shapes and its own backup must import. Malformed files with field-level damage still fail the import atomically.

## Where repairs surface

Reads are pure: the repair exists in the returned value and is re-derived identically on every read (and on every device - the rules are functions of record data only, no clocks). It persists when the value is next saved, or when the reconciliation pass runs. `subscriptionReadRepairs()` reports the repairs the current read applies - the recompute-on-read shape of `unreadableSubscriptionCount` - and Today renders one aggregate needs-review card naming the affected subscriptions, because a repair that closed an open pause episode decided something for the user.

The repaired episode's `updatedAt` is deliberately untouched: a repair is not a user statement, and stamping it would need a clock the domain does not read.

## The reconciliation pass (spec §5.3 v2.0)

`reconcile(at:)` on the store is the deterministic post-sync convergence pass Wave 6B will run after sync settles.
It is safe to run at any time (on an unsynced store it does nothing), idempotent, and every decision inside is a pure domain rule over record data, so devices running it independently converge:

1. **Duplicate ledger twins** - live rows sharing `(subscriptionID, expectedDate)`, the shape two devices' independent materialization passes produce. The earliest `createdAt` (tie: id) survives; any acknowledgement counts (earliest non-nil folds in) and any confirmation counts (the earliest-created non-`.upcoming` twin donates state, `userConfirmedAt`, `actualAmountCents`; an already-confirmed winner keeps its own answer). Losers are tombstoned.
2. **Rival open cancellation episodes** - `CancellationEpisode.closingSupersededRivals`, the same rule the import merge uses (one function, two callers): newest `markedCancelledAt` stays open, the rest close as `.superseded` at its start.
3. **Read-repair persistence** - subscriptions whose §4a read closes an episode are written back, so convergence is durable rather than re-derived per read. The two held shapes persist nothing; they self-heal when their child record arrives.

What it does NOT do: it never resurrects a tombstone, never touches watermarks, and never merges records that are individually valid and distinct - it only resolves the three shapes above.

## The four §8 prerequisites, and what each does NOT protect against

All four exist and are tested with sync off - the only time they can be tested honestly - because they exist to be used on the worst day.

**1. The automatic pre-enable snapshot** (`SyncActivationService.enableSync`).
Writes a full export to the user's Documents directory (visible in the Files app - `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`), and flips the sync flag ONLY after the file is durably on disk: a failed export means sync stays off.
Does NOT protect against: anything created after the snapshot (it is a floor, not a mirror); loss of the device itself (the snapshot lives beside the data it backs up); and a user who deletes the file from Files.

**2. The runtime kill switch** (`SyncState.killSwitchEngaged`, consulted by `OttoContainerFactory.mainStoreSyncMode`).
A `UserDefaults` flag readable before any container exists, sitting on the factory's real decision path NOW - so when 6B adds the cloud case, the brake is already load-bearing and tested, not freshly wired the day it first matters.
It beats the enable flag unconditionally, and disengaging restores the previous state.
Does NOT protect against: sync already in flight (it takes effect at the next launch); other devices, which keep syncing with the cloud copy; and it removes nothing, local or cloud - stopping the bleeding is all it does.

**3. The zone-purge action** (`SyncActivationService.purgeCloudZone` over the `CloudZonePurging` seam).
Refuses unless the kill switch is engaged - purging a zone that devices still sync re-uploads local copies into the fresh zone, which is resurrection at zone scale.
Until 6B supplies the CKDatabase implementation, the default purger THROWS rather than pretending a purge happened.
Does NOT protect against: other devices' local copies (a cloud purge deletes nothing on any device); an offline device re-enabling later and re-creating the zone from its own data; and it cannot be exercised against a real container until 6B - **its cloud half is the one prerequisite that ships untested against production CloudKit**, which is why 6B's plan must test it against a real container before enabling sync for real data.

**4. The sync-aware restore** (`restore(_:at:)`).
A restore now UPSERTS every record by id and TOMBSTONES what the snapshot does not carry - children included, via an explicit diff that is the whole-database authority `save` deliberately no longer has.
Under mirroring it syncs as ordinary edits: no mass cloud deletion, no hard-delete for offline devices to resurrect into.
Does NOT protect against: an offline device pushing post-snapshot EDITS over restored rows when it comes back (last-writer-wins still applies field-by-field - restore rewrites data, it does not freeze it); and it should still be run behind the kill switch during an incident, which nothing currently enforces mechanically.

**The honest operational rule for 6B remains** (from the readiness audit): the export file is the only trustworthy artifact, and sync must not be enabled for real data before the kill switch and the pre-enable snapshot exist. They now exist; the four manual gates and 6B's two-device verification still stand between this code and real data.
