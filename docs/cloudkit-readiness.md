# CloudKit readiness audit - Wave 6A

**Purpose:** the report-only audit Wave 6A's prompt calls for, answering five questions before Wave 6B writes any CloudKit code.
Everything below was checked against the code at this commit (schema `OttoSchemaV3`, the frozen schema), not against the spec's prose.
Nothing in this document changed behaviour; findings are triaged with the door still open.

**Reading order:** questions 3 and 4 contain the findings that should gate 6B's design; question 5 contains the one this document most wants remembered.

---

## Question 1 - does every model satisfy the CloudKit constraints?

**Yes, verified against V3 - after fixing the assertion itself, which had silently gone stale.**

The Wave 2 compatibility assertion (`CloudKitCompatibilityTests`) walks every entity in the schema and asserts: no unique attributes, every attribute optional or defaulted, every relationship optional with an explicit inverse, no `.deny` delete rules, plus a count so a new model cannot dodge the walk.
All of it passes against V3's eight models, including the new `StoredEvidenceNote`.

**The finding: the assertion was still pointed at `OttoSchemaV2` when this wave opened.**
It kept passing - green, meaningless - while the live schema moved to V3.
It now asserts V3, its coverage count is 8, and it gained a check that nothing in the synced schema is device-scoped (no `lastMaterializedThrough` attribute anywhere, no watermark entity).
The lesson is the Wave 4 one again: a green check is only evidence about what the check actually looks at, and version-pinned checks need a tripwire that fails when the version moves.
Worth carrying to Kept.

**What it actually checks versus what it assumes:**

- It CHECKS the schema declaration - `Schema(versionedSchema:)` entities in memory.
- It does NOT check the store artifact (the migration tests now do that with raw SQLite, separately).
- It ASSUMES the constraint list is complete.
  CloudKit also dislikes: ordered relationships (none used), undeployed production schema changes (a 6B operational concern, not a code one), and very large string/asset values (evidence note text is unbounded - fine in practice, but nothing enforces a ceiling).
- It ASSUMES `cloudKitDatabase: .none` keeps staying `.none` everywhere it should.
  6B will flip exactly one configuration (the main store's); the device-state container's `.none` must be permanent, and only the factory's comment says so.

## Question 2 - what is left in the synced schema that shouldn't sync?

**Swept every V3 field; nothing device-scoped remains.**

- The watermark - moved this wave, verified at the SQLite level (see the report).
- Settings - already outside the schema (`UserDefaults` via `SettingsStore`), excluded from export.
- The third thing: **looked, and found none that is device-SCOPED - but one field is device-SHAPED in its merge, and one is worth a deliberate look.**
  - `unansweredCheckCount` (restating Wave 8.5's Question 6, now with the per-record reading): two devices each rolling the same unanswered watch forward write the same count and converge; they diverge only when the devices disagree about `today`.
    Last-writer-wins is acceptable; no field moves.
  - `StoredBillingEvent` rows are *device-produced* even though they are user data: each device's scheduler materializes its own rows.
    The rows belong in the synced schema - they carry confirmations and reminders state - but their PRODUCTION is per-device, which is what makes Question 3's duplicate-row finding possible.

## Question 3 - what breaks under partial sync?

§3.5's rules assume eventual consistency; these are the places the code currently assumes immediate consistency instead.

1. **Duplicate ledger rows from concurrent materialization - the sharpest one.**
   `materializeEvents` dedups on `(subscriptionID, expectedDate)` against the rows *visible locally at pass time*.
   Two devices that each run a pass before the other's rows arrive both create a row for the same charge date, with different client-generated ids; when sync converges, both rows exist everywhere and nothing ever removes either.
   The user sees every upcoming charge twice, and confirming one leaves the twin `.upcoming` forever.
   Spec §5.3's "the dedup makes the duplication invisible" holds only when sync delivers before the pass runs - it is a *prevention* dedup, not a *reconciliation* dedup.
   **6B needs a post-sync reconciliation rule** (merge live `.upcoming` twins by `(subscriptionID, expectedDate)`, deterministically - e.g. keep the lexically-smaller id, prefer any non-upcoming state over `.upcoming`).
2. **A record arriving before its parent.**
   Mostly handled by design: reads skip unmappable records with a log ("in domain terms it is not there yet"), the billing-event scalar `subscriptionID` survives a missing parent, and a dangling `paymentMethodID` renders as "Unknown payment method".
   But two child-before-parent shapes degrade visibly:
   - A `.trial` subscription arriving before its trial term is refused by mapping, so the subscription is invisible AND `unreadableSubscriptionCount` reports it - the "N subscriptions could not be read" warning will flicker during ordinary sync.
   - A `.paused` subscription arriving before its open pause episode is refused by the §5.3a invariant check, same flicker.
   Both self-heal when the child arrives; the immediate-consistency assumption is that *unreadable means damaged* - under sync it usually means *early*.
   6B should either suppress the unreadable-count surface while sync is settling, or count sync-plausible shapes separately from true damage.
3. **A cancellation-status subscription arriving before its episode** renders the §5.2b "unwatched - needs review" card in Today.
   Correct for true invariant violations, alarming as a transient; same remedy as above.
4. **The §5.2b invariants themselves are stricter than eventual consistency.**
   `checkPauseInvariants` refuses shapes that CANNOT be produced by one device but CAN be produced by two correct devices mid-sync (see Question 4).
   Refusal was the right posture when the only writer was this device; under sync, refusal turns a transient into an outage.

## Question 4 - what does two-device conflict resolution do to the episode tables?

Wave 8.5 noted the pre-6 import merge resolves nested pause episodes wholesale by the subscription's `updatedAt`, and that this dissolves under CloudKit's per-record sync.
Walked through per record:

1. **Per-record sync makes episodes individually mergeable - the dissolution is real and mostly good.**
   A pause episode edited on device A and a rename on device B no longer fight; each record merges on its own `updatedAt`-ish last-writer-wins.
2. **But the embedded-save path still assumes it owns the whole array - this is the one that loses data.**
   The domain `Subscription` embeds `pauseEpisodes`; `OttoStore.save` syncs them by id and **soft-deletes any stored episode absent from the domain array** ("absence is deliberate removal, never drift").
   Under sync that contract is false: device A loads a subscription, device B's new pause episode syncs into A's store, A saves an unrelated edit from its stale in-memory value, and A **tombstones B's episode**.
   Silent, and it propagates.
   The same mechanism now exists for evidence notes (added this wave, same sync-by-id pattern) and for the trial slot.
   **This must be redesigned before 6B enables sync** - e.g. the save path only tombstones episodes it can prove the user removed (an explicit removal list), or the domain stops embedding and episodes get their own repository writes like cancellation episodes have.
   This is, in my view, the single most important pre-6B code change this audit found.
3. **Two devices pausing independently → two open pause episodes → the subscription becomes unreadable on every device.**
   `checkPauseInvariants` throws on `openPauses > 1`, mapping skips the record, and there is no repair flow.
   A benign concurrent action (both spouses pause the gym membership) makes the subscription vanish from all lists until someone edits SQLite.
   6B needs a convergence rule, and the import merge already states it: keep the newer open episode, close the older as superseded/resumed - applied post-sync, not just at import.
4. **Two devices cancelling independently → two open cancellation episodes.**
   No invariant throws (episodes are fetched, not embedded), so nothing becomes unreadable; `openEpisode` returns the newest open one and the older keeps rolling forward toward escalation - a zombie watch generating cards.
   The import merge's rule (close the older as `.superseded`, counted) exists precisely for this and should run as a post-sync reconciliation too.
5. **Answering verification on one device while the other rolls the watch forward** merges per-field: the closure (endedAt/outcome) wins on one record, and the fold's design helps here - closure and state no longer fight, because closing IS the resolution and the live state is vestigial afterwards.
   This is a place the v1.9 folding genuinely reduced the conflict surface.
6. **`statusAtStart` and the subscription's own status** are single fields with last-writer-wins; an un-cancel racing an archive converges to one device's story, and the loser's episode history still tells the truth.
   Acceptable: history is append-only, and nothing is deleted.

## Question 5 - what is the rollback story if CloudKit sync goes wrong after real data exists?

**Concretely and pessimistically: today, there isn't one - there is a backup story, and the difference matters.**

What exists: the export file (complete, versioned, decodes forever, atomic restore) and soft deletes everywhere.
What does not exist: any way to stop sync, purge the cloud copy, or restore without the restore itself syncing.

Walking the failure through:

1. A merge disaster (say, finding 2 above tombstoning episodes) propagates to every device *before anyone notices* - sync is the delivery mechanism for the damage.
   Soft deletes cap the blast radius: tombstoned rows are recoverable in principle, but no UI reads them back.
2. The instinctive rollback - restore a pre-incident export - makes it WORSE with sync on: `restore()` hard-deletes every record and re-inserts.
   Under mirroring that is a mass CloudKit deletion followed by a mass insertion, and any device that was offline with unsynced changes will re-upload ghosts into the freshly restored world.
3. Turning sync off is not currently possible: `cloudKitDatabase` is a build-time decision in the factory, so "disable sync" means shipping a build.
   And after disabling, the cloud copy persists; re-enabling later merges the STALE cloud data back over whatever was restored locally - resurrection, the exact failure §3.5's tombstones exist to prevent, but at the store level where tombstones cannot help because `restore()` hard-deletes.
4. Purging the cloud copy (delete the record zone) has no code, no UI, and cannot be improvised during an incident.

**What 6B must build BEFORE enabling sync, in order of importance:**

- An automatic local export snapshot taken immediately before sync is first enabled (and ideally before every schema-relevant app update).
  This is cheap, uses only machinery that already exists, and converts "there isn't one" into "there is a point to roll back to".
- A sync kill switch (runtime, not build-time), so damage can be stopped without an App Store release.
- A zone-purge maintenance action (delete the CloudKit zone, wipe local stores, re-import from a chosen export), tested against a real container before anyone needs it.
- A restore path that is sync-aware: with sync on, restore must either require the kill switch first, or be redesigned to write tombstones instead of hard deletes.

Until those exist, the honest operational rule for 6B is: **the export file is the only trustworthy artifact, and sync must not be enabled for real data before the kill switch and the pre-enable snapshot exist.**

---

## Summary of pre-6B work this audit implies (report only - none of it done this wave)

| Priority | Item | From |
|---|---|---|
| 1 | Sync-aware embedded-array saves (pause episodes, evidence notes, trial): absence must stop meaning removal | Q4.2 |
| 2 | Pre-enable export snapshot + runtime sync kill switch + zone purge action | Q5 |
| 3 | Post-sync reconciliation passes: duplicate `.upcoming` twins; two open pause episodes; two open cancellation episodes | Q3.1, Q4.3, Q4.4 |
| 4 | Soften the unreadable/needs-review surfaces for sync-plausible transients | Q3.2, Q3.3 |
| 5 | A tripwire so version-pinned checks fail when the schema version moves | Q1 |
