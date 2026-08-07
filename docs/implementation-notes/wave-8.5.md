# Wave 8.5 - Model lock and schema freeze

Date: 2026-08-07

The last wave in which any model change is cheap.
Wave 8's report surfaced two findings that are the same modelling error - one-to-one shapes for things that recur - and this wave lands the two fixes, then sweeps every §5 relationship for siblings, because relationship cardinality is the one change class that cannot be made cheaply after Wave 6 turns on CloudKit.
No new user-facing features beyond what the model changes require; the product of this wave is a schema worth freezing, and the review that says so.

## What exists after this wave

- **Spec v1.8** replaces v1.7 (`090ac87`), committed alone - the schema-freeze candidate.
- **The episode tables** (spec §5.3a), in both layers (`9e978ed`).
  `CancellationEpisode` replaces the one-to-one `CancellationRecord`: one row per cancellation, carrying the whole v1.7 verification machinery plus `statusAtStart` (what the cancellation interrupted - what an un-cancel restores), `endedAt`, and an `outcome` (`.verifiedStopped`, `.abandoned`, `.superseded`).
  `PauseEpisode` replaces the `pausedOn`/`pauseEndsOn` field pair: one row per pause, with `startedOn` (the §7.2 price-freeze point, optional because pre-Wave-7 pauses never recorded it), `scheduledResumeOn`, `endedOn`, and `.resumed`.
  The current episode is the one with no end date; nothing is ever cleared on exit from a state - exiting writes an end date.
  Pause episodes are EMBEDDED in the domain `Subscription` (like the trial) because `effectiveStatus(asOf:)` derives from the current pause and must not need a repository; `pausedOn`/`pauseEndsOn` survive as derived accessors onto the open episode, so nearly every read site was untouched and the two values can never disagree with the history again.
  Construction enforces the new invariants everywhere data enters: at most one open pause episode, a `.paused` subscription always has one, an open one never coexists with stored `.active`/`.trial` - precondition in the domain, thrown errors in the mapping and the wire format, same §5.2b pattern.
- **Schema V2 and the V1→V2 migration.**
  `OttoSchemaV1` is now a frozen legacy declaration (exact shipped shapes - it is the migration source and must match stores byte for byte); `OttoSchemaV2` adds `StoredCancellationEpisode` and `StoredPauseEpisode` and drops the old slot and fields.
  A CUSTOM migration stage - permitted exactly because CloudKit is not on yet - carries the data across: every v1 cancellation record becomes an episode (a `verifiedStopped` one closes at its verification instant, everything else stays open, `statusAtStart` honestly nil), and every v1 pause becomes an OPEN episode, including the cancelled-mid-pause and archived-while-paused shapes, which keep their open episode because billing never resumed.
  The upgrade rule is written ONCE in the domain (`CancellationEpisode.legacyClosure`, `PauseEpisode.legacyEpisodeExists`) and shared by the SwiftData migration and the export format's v1 import, so the two paths cannot drift.
- **The un-cancel** (spec §5.4): `abandonCancellation` closes the open episode as `.abandoned` - "I thought I'd cancelled this and hadn't" is exactly the data this product is about, so it is kept, never deleted - and restores `statusAtStart`, validated against what the subscription still carries (a recorded `.trial` without a term falls back to `.active`; a nil from migrated data derives pause-episode → `.paused`, term → `.trial`, else `.active`).
  Episode-first ordering plus a heal path in both `abandonCancellation` and `startCancellation` means a kill between the two writes converges on re-run from either direction.
  Detail's cancellation section grew the one button the flow needs ("I'm not cancelling after all"); re-cancelling afterwards opens a SECOND episode and history accumulates.
- **The watermark now freezes during cancellation states**, the same mechanism as the indefinite pause: a pending cancellation's exit (un-cancel) re-expects charges RETROACTIVELY, so no pass may vouch for the watched window.
  Un-cancel then backfills every charge date the watch covered on the next ordinary pass; for data migrated from before the freeze existed, the abandon flow also rewinds the watermark behind the episode's watched date (§5.3 v1.7's rewind rule, belt to the freeze's suspenders).
- **Invalidation never touches past-dated rows** (spec §5.3 v1.8) - the Wave 8 finding.
  `invalidateOutdatedUpcomingEvents` now skips every row dated today or earlier: a price edit no longer silently deletes a passed-unconfirmed charge from the ledger, and a row dated today survives because whether today's charge already landed is unknowable at edit time.
- **Export format v2**, under v1.8's stated policy: any field change bumps the version, additive included, because Codable silently drops unknown keys.
  v2 writes `pauseEpisodes` per subscription and a top-level `cancellationEpisodes` array; v1 files decode forever, upgraded once at read with documented defaults, and the synthesized pause episode's id is DERIVED from the subscription id so re-importing the same v1 file cannot duplicate it.
  The merge's old single-slot rule became: at most one OPEN episode per subscription - a merge that unites two open cancellations keeps both rows and closes the older as `.superseded`, counted, where v1 discarded the loser outright.
- **`docs/schema-freeze-review.md`** - the sweep itself: all six questions against every model, explicit verdicts, the ambiguous items written up instead of guessed, and the regret-ranked list.
  That document is the wave's actual deliverable and gates Wave 6.

## Decisions worth recording

- **Pause episodes have no scalar `subscriptionID`** (trial precedent: nothing fetches a pause except through its subscription); cancellation episodes keep theirs (they are fetched by predicate).
- **Archive leaves an open pause episode open.** A subscription cancelled mid-pause died paused; writing a resume day it never had would be fiction.
- **`SubscriptionStatus.cancelled` stays, meaning reserved in writing** (see the review) - no flow has ever produced it, so it can still be assigned a meaning safely, and removing a wire case the week the format freezes buys nothing.
- **Migration timestamps borrow the source record's** - migration reads no clock, and the subscription's `updatedAt` is the closest instant v1 recorded to the pause actually starting.

## Test-infrastructure note (not a product issue)

SwiftData keeps a process-global, name-keyed model registry, and V1/V2 deliberately share entity names (V1 must match shipped stores).
Building both schemas CONCURRENTLY in one test process races that registry and dies in `ModelCoders` - the app never does this (it builds exactly one container), but parallel test suites did.
Fix: every `ModelContainer` creation in `OttoPersistenceTests` goes through one lock, and the migration test holds it across its whole V1-touching phase.
Hammered five parallel runs clean; worth carrying to any future project that keeps two live schema versions (Kept included).

## verify.sh against this wave's HEAD

See the wave report; the run was from a clean clone per the script's contract.

## Where the next wave starts

Wave 6 (CloudKit) is authorized by the schema-freeze review, not by default.
Its first schema act is moving the watermark into the local-only configuration - restated in the review's regret list because it is the one deferred item with a failure mode this app exists to prevent.
Four manual items still gate it, none of them code: the compressed-timeline trial test on a device, the `BGAppRefreshTask` LLDB observation, the hands-on add-a-subscription pass, and exporting once by hand to look at the JSON.
