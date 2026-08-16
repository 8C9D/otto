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

## ⛔ Wall-clock timestamps are a merge input, and the device clock is not monotonic

**Found Aug 2026, in real exported data.** The export carries records whose `deletedAt` PRECEDES their `createdAt`:

| Record | createdAt | deletedAt |
|---|---|---|
| `cancellationEpisode 9ACC5DC0` | 2026-08-10T14:11:05Z | 2026-08-08T17:32:09Z |
| `billingEvent EC133708` | 2026-08-10T14:17:32Z | 2026-08-08T17:32:09Z |

Both belong to the "Gate Test" subscription, written under the advanced clock of procedure 1 (the compressed-timeline trial test) and tombstoned after the clock was restored.
**This is not hypothetical drift: clock manipulation is a documented step in this project's own verification procedure, and it has now reached persisted data.**
A user can set the device clock by hand for their own reasons; nothing in the app can prevent it, and nothing currently detects it.

### Q1. What does "earliest `createdAt` wins" do with a future-clocked stamp?

`BillingEvent.reconcilingDuplicates` (`SyncReconciliation.swift:32`) sorts `(createdAt, id)` ascending and keeps `.first`.

- A row written under an **advanced** clock sorts LATE and **loses**.
- A row written under a **restored or rewound** clock sorts EARLY and **wins** - *even though it was written later in real time.*

The trial-gate procedure produces exactly both populations in one session, so the two orders genuinely disagree.
**Convergence is not at risk** - every device sorts the same stored data identically and reaches the same answer, which is the property the rule was designed for.
What breaks is the correspondence between timestamp order and causal order: **the rule means "smallest timestamp", and only means "the original" while the clock is honest.**

The stakes are not limited to which row survives, because the winner absorbs the losers' state: `acknowledgedAt` is the `min` over losers (itself a clock comparison), and `state`, `userConfirmedAt` and `actualAmountCents` are donated by the earliest-created non-`.upcoming` twin.
A wrong winner can therefore adopt the wrong confirmed amount - a money field.
Today's artifacts are tombstones and this rule reads live rows only, so nothing is currently mis-merged; **the mechanism does not know that, and the next occurrence need not be a tombstone.**

### Q2. What else decides on `createdAt` / `updatedAt`?

Seven places. Ordered by how much damage a bad timestamp does:

| Where | Rule | Effect of a dishonest clock |
|---|---|---|
| `ImportResolution.swift:161` | `record.updatedAt > existing.updatedAt` - **last-writer-wins**, the merge rule for every imported record | ⛔ **The worst case.** A future stamp is *sticky*: it wins every merge until real time catches up. The Aug 10 stamps above would have beaten every honest edit for two days |
| `SyncReconciliation.swift:32` | duplicate ledger twins, earliest `createdAt` | ⛔ Q1 above - wrong winner donates state and `actualAmountCents` |
| `ImportResolution.swift:247` | multiple live default payment methods: `max(updatedAt, id)` | Picks which card is default |
| `SubscriptionReadRepair.swift` | last-resort close day for a degenerate pause episode = **the UTC day of its `createdAt`** | A future `createdAt` becomes a future calendar day - a clock value promoted into billing-relevant data |
| `SubscriptionMapping.swift:38`, `CancellationEpisodeMapping.swift:89` | `(createdAt, id)` ordering when mapping stored children | Chooses which child is canonical |
| `Insights.swift:248,331`, `OttoStore+PriceChanges.swift:47` | `(effectiveDate, createdAt)` | `createdAt` breaks ties *within one effective date* - a same-day price change can order wrongly |
| `CancellationEpisode.swift:233` | `liveEvidenceNotes` by `(createdAt, id)` | Display order of dispute evidence only |

### Why this matters specifically for 6B

CloudKit mirroring resolves field-level conflicts by last-writer-wins, and the app's own import merge is the same rule at record level.
**Both assume the clock only moves forward.** A record stamped in the future wins every conflict until the world catches up; a record stamped in the past can never win one, so a genuine later edit is silently discarded.
Note also that §8 prerequisite 4 already documents "last-writer-wins still applies field-by-field" as its residual risk - **this finding is that risk's input being untrustworthy**, which is a level below where the audit had been looking.

The fix was a design decision for 6B, not a patch. The options, as they stood:

1. **Reject the premise**: order by something monotonic per device - a Lamport/hybrid-logical clock or a per-record version counter - and keep wall-clock stamps for display only. Correct, and the largest change.
2. **Clamp on write**: never let a record's `updatedAt` go backwards, and never let `createdAt` exceed the write instant. Cheap, local, and does not help across devices whose clocks disagree.
3. **Detect and refuse**: treat `deletedAt < createdAt` (and any backwards `updatedAt`) as a §4a read-repair shape - surface it rather than merging on it. Cheapest, and at minimum makes the condition visible instead of silent.

### Decided 2026-08-16: options 2 and 3 combined; option 1 rejected

Full record in `DECISIONS.md` ("Sync safety - the monotonicity decision").
What now exists:

- **Write clamps** (`monotonicStamp(_:notBefore:)`, `RecordStamps.swift`): every mutation stamp is `max(now, current updatedAt)`, every tombstone stamp is floored at the record's `createdAt` - domain transitions, the store's delete cascades and restore path, the reconciliation pass, and the service-layer stamping sites.
  The observed shape (`deletedAt < createdAt`) can no longer be written by this device, whatever the clock does.
- **Order repair at import** (`resolveImport`): before any rule compares them, every record on BOTH sides - embedded children included - has `updatedAt`/`deletedAt` raised to its own `createdAt`.
  Pure function of record data, so every device converges; `createdAt` is never moved, because the ledger merge orders on it.
  Counted in `ImportSummary.timestampOrderRepairs` and logged on the `import end` line.
- **Future-stamp defusal at import**: any stamp ahead of the import instant is clamped to it, both sides, both strategies, so a future stamp cannot stay sticky and win merges until real time catches up.
  Counted in `ImportSummary.futureStampClamps`, same log line.

Option 1 was rejected because CloudKit's own field-level conflict resolution cannot be fed a logical clock - it would be the largest change with partial coverage - and is held in reserve if two-device damage is ever observed.
**Accepted residual**: honest cross-device clock skew still orders last-writer-wins wrongly; that is §8 prerequisite 4's documented residual, and the snapshot / kill switch / restore floor is the mitigation.
Q1's earliest-`createdAt` caveat also stands: a `createdAt` written under a dishonest clock has no local reference to repair against, so the ledger-twin winner can still be the wrong twin - the clamps bound the damage (no regressive or future stamps survive a write or an import) without claiming to restore causal order.

**The standing rule holds: a device clock the user can set is not a monotonic source, and no merge rule may assume it is.**

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
