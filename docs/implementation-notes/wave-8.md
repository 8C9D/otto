# Wave 8 - Export/import, settings, accessibility

Date: 2026-08-07

The last wave before Wave 6 turns on CloudKit.
Export/import is built as what it is - the CloudKit escape hatch (§3.5) - and this note carries the last cheap §5 scrutiny, because after Wave 6 a model change is a schema migration against data on two people's phones.

## What exists after this wave

- **Spec v1.7** replaces v1.6 (`0989920`).
- **The §5.2a v1.7 stored-status rule, enforced structurally** (`0b61250`).
  `Subscription.status` is renamed `storedStatus`; a SwiftLint custom rule makes any mention of it an error in OttoUI sources, OttoRepositories, and the app target (tests are exempt - asserting what a flow persisted is exactly a stored read).
  Layers 3-5 now go through `effectiveStatus(asOf:)` or new intent-named domain transitions (`pausing`, `resuming`, `markingCancellationPending`, `archiving`) and record-preserving edit helpers (`editedStatus`, `editedTrial`), so every persisted lifecycle write and its guards live in layer 1.
  Fixed instances the rule caught: `caughtUpCancellationRecords` and `SubscriptionsStore.refresh` (the Wave 7 report's flags), the scheduler's identical filter, both status badges, the list's status filter, Detail's pause row, and the pause section's branching.
  One was a live display bug, not just a pattern: Detail showed "Resumes Sep 1" forever after Sep 1 had passed, because the row keyed off stored `.paused` instead of the derivation.
- **The §5.3 v1.7 watermark rewind** (`0b61250`), as a pure function `watermarkAfterEdit(from:to:trackedSince:asOf:)` applied at `SubscriptionsStore.save`, the single Add/Edit choke point.
  An edit that moves the billing sequence earlier rewinds the watermark to just before the first newly expected charge; the rewind is floored at the earliest ledger row ever created (tombstones included), so a Mode-A anchor correction cannot manufacture pre-entry history.
  Status transitions are excluded by design - the flows' freeze-and-backfill semantics own those, and a naive sequence diff on resume-from-indefinite would resurrect the pause's deliberately tombstoned rows.
  The same path enforces that a save never ADVANCES a watermark - only a ledger pass does - which also closes a stale-snapshot hazard where re-saving an edit could undo its own rewind.
- **Export/import** (`568da8d`), the wave's centrepiece.
  The wire format is its own versioned type set (`OttoExport`, format 1), not the domain or persistence models re-encoded: calendar days as "YYYY-MM-DD" strings, instants as reference-date seconds (bit-exact round-trip), money as integer cents, enum strings pinned by a tripwire test.
  Export is complete - every field of every model, tombstones included - except the device-local watermark, absent by design (§5.3), and it THROWS on an unmappable record rather than exporting a backup with a silent hole.
  Import is version-checked first (a future format refuses outright with a message that says what to do), validated whole (§5.2b and §5.4 invariants are thrown errors before any domain precondition could trip), resolved purely (`resolveImport`), and applied atomically by `OttoStore.restore` - refuse-first structure, one `save()`, no failure path between the first mutation and the save.
  The conflict policy is explicit: a non-empty database always gets the merge-or-replace question; merge keeps both sides and lets the newer `updatedAt` win per record, replace becomes exactly the file and counts what it removed; nothing is ever discarded without appearing in the summary counts.
  The charges CSV ships alongside, lossy and one-way on purpose, and the UI copy says which file round-trips.
- **Settings** (`8efa336`), spec §7.1 item 9: default renewal and trial lead days and the trial buffer (applied to NEW entries only - existing subscriptions keep their own values), the notification time (read live by every scheduling pass through a provider, so background passes honour it, and changing it reschedules immediately), the notification permission state with a route to Settings.app when denied, the export/import entry points via the share sheet and file importer, and the iCloud placeholder Wave 6 fills in.
- **The accessibility pass** (`beb9052`) - findings below, one fix.

## verify.sh against this wave's HEAD

Passed clean from a clean clone: OttoDomain 208, OttoPersistence 74, OttoUI 113 - 395 on the mac host, plus 8 Dynamic Type tests that exist only on a simulator (verified locally via `xcodebuild test -scheme OttoUI-Package`), 403 total.

## Accessibility: what the pass found

Wave 3's from-the-start approach mostly held.
Every composite row combines into one VoiceOver element; every status, expiry, and verification state is a Label whose text and symbol carry the meaning with colour only reinforcing; there is not a single `lineLimit`, `minimumScaleFactor`, or fixed frame in any OttoUI view, so nothing truncates by construction; reading order is standard sections and combined rows throughout.

1. **One real gap, found and fixed: the subscription list row was silent about status.**
   The row's custom accessibility label - which REPLACES the combined children - listed name, price, cadence, and next date but not the status, so VoiceOver never heard "Trial", "Paused", or "Cancelled" on the one screen that lists everything.
   The status badge was its only carrier.
   Fixed by speaking the effective status, pinned by a simulator test.
   The lesson for future screens: `accessibilityElement(children: .combine)` is safe by default, but the moment a custom label is added, every fact the row shows has to be restated in it.
2. **Left in place, flagged for an overrule: the Insights 12-month cluster emphasis is shade-only** (`.primary` vs `.secondary`).
   I judged it emphasis rather than a sole carrier - the amount itself is the data and the footer explains clusters - but a VoiceOver or low-vision user cannot tell which months are flagged as clusters.
   If you consider the cluster flag meaning-bearing, it needs a spoken suffix or a symbol.
3. **Contrast relies entirely on system semantic colours** (orange/red/green/secondary on system grouped backgrounds) in both modes; no custom colours exist anywhere.
   Verified by inspection, not measured with a contrast tool.

## Findings and deviations (not polite)

1. **A price edit strands past unacknowledged ledger rows, and v1.7's rewind rule does not cover it.**
   §5.3 invalidation tombstones every live `.upcoming` row whose amount no longer matches - including rows dated in the past - and materialization's window floor is `min(watermark, today)`, so those rows never come back.
   Edit a price and any not-yet-acknowledged past charge rows silently vanish from the ledger.
   This is the same stranding class as the pause case v1.7 generalized, but it is an AMOUNT change, not a date change, so the "moves the billing sequence earlier" rule I implemented (dates only, per the spec's wording) does not catch it.
   I did not silently extend the rule, because the right fix is a spec decision: either amount edits also rewind (recreating past rows at the NEW price, which rewrites what was actually expected), or - my lean - §5.3 invalidation should not tombstone past-dated rows for amount mismatches at all, because a past expected charge at the old price is a record of what was expected then.
   This is a §5 behavioural gap and Wave 8 was the cheap wave to decide it; it is now a Wave 6-adjacent decision.
2. **§5.4 has no path out of a cancellation - an accidental "Mark as cancelling" is irreversible in-app.**
   Every exit from `.cancellationPending` leads to `.archived` or `.stillCharging`; nothing un-cancels.
   Compounding it, storage holds ONE cancellation record per subscription forever (the 1:1 slot), so any future un-cancel-and-recancel design overwrites the first record's history.
   No tracker user will care until the day they tap it by mistake; a spec decision costs a paragraph now and a migration later.
3. **Resume erases the pause's history.**
   `resuming` clears `pausedOn` and `pauseEndsOn`, so after resume nothing records that a pause happened or how long it lasted.
   §7.2's paused-spend line only needs the CURRENT pause, so nothing breaks today - but any future "what did this cost me last year" question meets a model that cannot answer across past pauses.
   A pause-episode child table is a field addition today and a CloudKit migration after Wave 6.
4. **The export format's version policy needs one sentence in the spec: ANY field change bumps the version, additive included.**
   `Codable` ignores unknown JSON keys, so an old app importing a newer same-version file would silently DROP the new field's data - the exact silent-hole class this app exists to prevent.
   The tripwire test pins format 1's strings, but the policy itself should be spec text, not code comment.
5. **Settings are device-local and outside the export, by design but worth stating.**
   Lead-day defaults, the trial buffer, and the notification time live in `UserDefaults`; they are not §5 model data, do not sync, and do not restore from a backup.
   Fine for v1; say it in the spec so Wave 6 does not accidentally promise otherwise.
6. **`paymentMethodID` is a reference with no defined meaning when dangling.**
   Nothing validates it on entry or import (deliberately - the method may be tombstoned or on the other device after Wave 6), and the UI silently shows "None recorded".
   Harmless today; after CloudKit, partial sync makes dangling references routine, and the spec should say that "dangling means unknown, render as none" is the policy rather than leaving it emergent.
7. **Interpretations this wave had to make** (each tested, none spec-backed): merge ties (equal `updatedAt`) keep the existing record so importing your own fresh export is a no-op; a merge that yields two cancellation records for one subscription keeps the newer and COUNTS the displaced one as removed (the one discard merge cannot avoid, made visible); two live default cards after a merge resolve to the newest default; the rewind floor with no ledger rows at all is today; export instants are Apple reference-date seconds (a future Android importer needs that constant, documented in the format header); the CSV is the charge ledger only, live rows only; the notification-time setting moves only the preferred slot while the trial evening last-call stays at 19:00.
8. **The Wave 5.5 segfault did not recur** in any run this wave.

## Still on the owner

1. The three manual device checks in `docs/manual-verification.md` - the compressed-timeline trial test is STILL the unmet ⛔ gate, and Wave 6 is now the next wave.
   Going through the one-way door with the app never once driven by hand remains the riskiest move available.
2. The GitHub remote - eight waves, CI never executed.
3. Two spec decisions from the findings above are cheap now and migrations later: the price-edit stranding rule (finding 1) and the un-cancel path (finding 2).
4. Try the export: add a subscription by hand, export, and open the JSON.
   It is the escape hatch this wave existed to build, and it has never been produced by a human hand.
