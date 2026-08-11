**VERDICT: PASS-WITH-FINDINGS**

Stage 4, commit range `62b4128..989ece0`, reviewed head `989ece0`.

The range holds four commits: the stage-3 review artifact (`ca11f5e`), stage 3's remediation (`c566ce6`), the R3-1 fix (`20d189a`), and a ledger bookkeeping commit (`989ece0`).

R3-1's fix is real, minimal, and does what the ledger says it does for the input the ledger names.
No schema change of any kind, in this range or anywhere on the round-2 branch.
No prohibited action by the builder.
Every guard I broke died with the line it guards, and the three falsification directions the ledger tabulates all reproduce exactly.
The non-Gregorian baseline this run created and then regressed is genuinely repaired: I re-measured **1 / 1 / 5** at `989ece0` against **1 / 1 / 7** at `62b4128`.

The findings are that **R3-1's predicate does not fire on the most likely form of the very device state it describes**, because deleting every subscription cascades to every child but leaves a payment method live — and the ledger's residual note describes that relationship backwards; that **the stage's own remediation of `reviews-2/REVIEW-3.md` finding 2 exists only in a commit message**, while the three ledger sentences that reviewer rejected are unchanged; and that **the new model-to-input guard covers only the one argument the reviewer happened to name**, so two other Today surfaces can still be deleted with all 191 tests green.

---

## Verification re-derived from scratch (nothing below is read from an artifact)

| measurement | `reviews-2/BASELINE-2.md` at `7a3cf54` | `reviews-2/REVIEW-3.md` at `62b4128` | re-derived by me at `989ece0` |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 533 (246 / 113 / 174) | exit 0, 551 (248 / 113→114 / 189) | **exit 0**, **554** (OttoDomain **248**, OttoPersistence **115**, OttoUI **191**) |
| `swiftlint --strict` | clean | clean | **clean** (and clean at `c566ce6` and `20d189a` individually) |
| simulator from `Packages/OttoUI/` | `** TEST SUCCEEDED **`, 101 / 65 / 20, 7 known issues | 102 / 70 / 30, 7 known issues | **`** TEST SUCCEEDED **`**, exit 0, **103 / 70 / 31**, **7 known issues** |
| `th_TH@calendar=buddhist` | 1 issue | 1 issue | **1 issue** (`DisplayFormattingTests.swift:49`) |
| `ja_JP@calendar=japanese` | 1 issue | 1 issue | **1 issue** (`DisplayFormattingTests.swift:49`) |
| `ar_SA@calendar=islamic-umalqura` | 5 issues | **7 issues** | **5 issues** — the documented baseline, restored |

The deltas reconcile exactly to the diff.
OttoUI 189 → 190 is `c566ce6`'s `theModelFeedsTheInput`; 190 → 191 is `20d189a`'s `mergeIntoAllTombstonedDatabaseReconstructsWatermarks`; OttoPersistence 114 → 115 is `20d189a`'s `restoreIntoAllTombstonedStoreReconstructsWatermarks`.
OttoDomain stays at 248 — the new public domain property ships with no OttoDomain test, which is finding 1's second half.
The simulator's 30 → 31 and 102 → 103 are those same two OttoUI-package tests.
I independently checked out `c566ce6` in a scratch clone and measured **OttoPersistence 114, OttoUI 190**, which is exactly what its message claims — `reviews-2/REVIEW-3.md` finding 3's defect (a commit message claiming a state the commit does not have) does not recur.

### The locale baseline, re-measured on both sides

At `62b4128`, in a scratch clone, through the harness `CalendarEraTests.swift:15-21` documents:

```
th_TH@calendar=buddhist          ✘ Test run with 189 tests ... failed ... with 1 issue.
ja_JP@calendar=japanese          ✘ Test run with 189 tests ... failed ... with 1 issue.
ar_SA@calendar=islamic-umalqura  ✘ Test run with 189 tests ... failed ... with 7 issues.
```

At `989ece0`:

```
th_TH@calendar=buddhist          ✘ Test run with 191 tests ... failed ... with 1 issue.
ja_JP@calendar=japanese          ✘ Test run with 191 tests ... failed ... with 1 issue.
ar_SA@calendar=islamic-umalqura  ✘ Test run with 191 tests ... failed ... with 5 issues.
```

The two extra `ar_SA` issues are gone and no new one replaced them: the five are `DisplayFormattingTests.swift:49,59,68,69` and `NotificationReconciliationTests.swift:170`, which is the pre-existing set.
**This stage restored the baseline it inherited broken.** That is the single most creditable thing in the range and it is stated accurately at `PROD-READINESS-2.md:210`.

### R3-1 falsified in all three directions the ledger claims

In a scratch clone at `989ece0`:

```
current.hasNoLiveRecords -> current.isEmpty
   ✘ ExportServiceTests.swift:181  await transfer.restoredWatermarkPolicies == [.reconstruct]
   ✘ Test run with 191 tests in 34 suites failed ... with 1 issue.

let reconstruct = true
   ✘ ExportServiceTests.swift:113  await transfer.restoredWatermarkPolicies == [.keep]
   ✘ Test run with 191 tests in 34 suites failed ... with 1 issue.

hasNoLiveRecords forced false
   ✘ ExportServiceTests.swift:167  buried.hasNoLiveRecords
   ✘ ExportServiceTests.swift:141  the EMPTY-database case
   ✘ ExportServiceTests.swift:181  the all-tombstoned case
   ✘ Test run with 191 tests ... with 3 issues; OttoPersistence 2 issues at RestoreIntoEmptyStoreTests.swift:101
```

All three reproduce. The empty case does route through the same predicate, as claimed.

### The stage-3 remediations each die with their own line

```
TodaySectionPlan.swift:90   notifications: model.notifications -> nil
   ✘ TodaySectionPlanTests.swift:319  (built.permission → nil) == .authorized
   ✘ TodaySectionPlanTests.swift:320  built.lastPassFailed → false
   ✘ TodaySectionPlanTests.swift:321  plan(built) → [needsAction] .contains(.coverageGap)
   ✘ 3 issues — exactly what c566ce6's message claims

OttoStore+Watermarks.swift:58-60  the EVENT fetch's `deletedAt == nil` predicate dropped
   ✘ DataTransferTests.swift:262            (fixture 1, a LIVE subscription)
   ✘ RestoreIntoEmptyStoreTests.swift:166   (the TOMBSTONED subscription — new)
   ✘ 2 issues, where `reviews-2/REVIEW-3.md` finding 6 measured 1
```

Finding 6 is genuinely closed: moving the fixture event to `2026-05-01` (`RestoreIntoEmptyStoreTests.swift:140-142`) makes the anchor the only value that can produce a pass, and the live-events rule is now guarded for the tombstoned case it is about.
I also re-ran R0-6's own falsification (reverting the subscription fetch at `OttoStore+Watermarks.swift:57`): still exactly 2 issues, so this stage did not disturb it.

---

## Findings

### 1. P2 — R3-1's predicate does not fire on the most likely form of the device state it names, and the residual note has the relationship backwards

**severity:** P2, not P1: the shipped behaviour is strictly better than before, nothing regresses, and the residual *is* disclosed as N2-3 rather than hidden.
It is P2 rather than P3 because the disclosure mis-describes which side is the common case, so a reader of the ledger will believe the reachable loss was closed when the narrow one was.

**evidence.**
`hasNoLiveRecords` (`OttoDataSnapshot.swift:43-49`) requires all five arrays to hold no live record.
`deleteSubscription` (`OttoStore+Subscriptions.swift:63-76`) cascades the tombstone to the trial, cancellation episodes, pause episodes, billing events and price changes — **but not to payment methods**, which are not children of a subscription.

Measured, with a throwaway probe suite in a scratch clone at `989ece0`, deleted afterwards. One payment method, one subscription with one billing event, then `deleteSubscription`:

```
PROBE live subscriptions: 0
PROBE live billing events: 0
PROBE live payment methods: 1
PROBE isEmpty: false
PROBE hasNoLiveRecords: false
```

So the device that has deleted every subscription and kept its card is **not** covered by the fix: `performImport` still takes `.keep`, still leaves every restored subscription with a nil watermark, and still loses the rows between the file's last charge and today.
That is R3-1's own failure, verbatim, on the state a user reaches by deleting their subscriptions.
`reviews-2/BASELINE-2.md:123` records that the real device in Gate 3 carries exactly that: *"Payment method returns, 3 subs billed to it ✅ Credit card ••XXXX Bank, default"*.

The second probe shows the other two survivors the ledger names cannot occur. Same store, a price change and a cancellation episode, then `deleteSubscription`:

```
PROBE2 live priceChanges: 0
PROBE2 live episodes: 0
PROBE2 hasNoLiveRecords: true
```

`PROD-READINESS-2.md:262` says: *"A device with no live subscriptions but a surviving payment method (or price change, or cancellation episode) therefore still takes `.keep` … the same loss R3-1 describes, **through a narrower door**."*
Two of the three named survivors are impossible, the third is the default outcome of the ordinary user action, and the door is **wider** than the one the fix closes, not narrower.

The predicate also has no guard distinguishing it from N2-3's own proposed alternative. Reducing `hasNoLiveRecords` to its first conjunct alone — which is exactly *"no live subscriptions"*, the predicate N2-3 calls "arguably" faithful — leaves the whole tree green:

```
OttoDomain      ✔ 248 tests passed
OttoPersistence ✔ 115 tests passed
OttoUI          ✔ 191 tests passed
```

Four of the five conjuncts are unexercised, and OttoDomain adds no test for the new public property at all (248 → 248).

**why the builder missed it.**
Every fixture the item exercises is payment-method-free: `ExportServiceTests.seededSnapshot()` (`:34-50`) builds one subscription and one billing event, so `for index in buried.paymentMethods.indices` at `:165` iterates zero times, and `allTombstonedStore()` (`RestoreIntoEmptyStoreTests.swift:94-103`) saves a bare subscription.
The one record type that actually decides the predicate is absent from every case the stage ran, so the predicate always answered `true` and the cascade rule was never the thing under test.

### 2. P2 — the stage's remediation of `reviews-2/REVIEW-3.md` finding 2 exists only in a commit message; the ledger sentences the reviewer rejected are unchanged

**severity:** P2. The code change is correct and is an improvement. What is missing is any trace of it in the document the run designates as its live record, while that document still asserts the thing the previous reviewer disproved.

**evidence.**
`git diff 62b4128 989ece0 -- PROD-READINESS-2.md` has six hunks — the work-list row, the REVIEW RANGES row, an ITEM 1 heading, and three inside ITEM 3 / ITEM 4 / NEXT ROUND. **No line of ITEM 2** (`:133-176`) is touched.
At `989ece0` the ledger still reads:

- `:165` — falsification row *"`TodaySection.input`'s read of the store (**the wiring**)"*. `reviews-2/REVIEW-3.md` finding 2 is explicitly that this label is on the wrong seam.
- `:168` — *"`TodaySection.input` is now a static factory over the stores"*, with no mention of the `input(model:overview:subscriptionsEmpty:)` overload that this stage added and that is now the guarded seam.
- `:170` — *"the two consequential seams either side of it (the input mapping and the card's own copy) are guarded"* — the sentence finding 2 rejected, restated unchanged.
- `:31` — the work-list row is still *"**RESOLVED** — `eb4a13b`"*, one commit, while rows 1 and 3 each list two (`a82d4e0` + `4b18420`, `db13abd` + `8ea8162`). R4-1's fix is now three commits: `eb4a13b`, `12fdcfc`, `c566ce6`.

The ledger's own convention makes this its job: `:122` — *"Recorded here because commit messages cannot be amended and the ledger is the live document."*
`c566ce6` also opened a *"Corrections to this stage's own record"* block for stage 3 (`:207-211`) and put findings 1, 3, 4, 5 and 7 in it. Finding 2 is the only one of the six with a code change and no ledger line.

And the cut itself is narrowed, not closed. In a scratch clone at `989ece0`, re-pointing `TodayView.overviewList` (`TodayView.swift:43-46`) at the surviving five-argument overload with `notifications: nil`:

```
✔ Test run with 191 tests in 34 suites passed after 0.050 seconds.
```

The five-argument overload (`TodaySectionPlan.swift:94-101`) is still internal and still reachable from the view, so the same deletion is a six-line edit rather than a one-token edit. That is progress, and the ledger says none of it.

**why the builder missed it.**
The remediation commit routed findings 3, 4, 5 and 7 to the ledger *because* they were "record corrections", and treated finding 2 as a code fix that therefore needed no record.
Finding 2 was both: a code defect and a false sentence about that code, and only the first half was answered.

### 3. P2 — the new model-to-input guard pins the one argument the reviewer named and leaves the other two exactly as they were

**severity:** P2, the same rating `reviews-2/REVIEW-2.md` finding 1 and `reviews-2/REVIEW-3.md` finding 2 carry for the identical shape: the code at HEAD is correct, and nothing would notice if two of Today's surfaces stopped being fed.

**evidence.**
`TodaySection.input(model:overview:subscriptionsEmpty:)` chooses three things from the model (`TodaySectionPlan.swift:86-91`). `theModelFeedsTheInput` (`TodaySectionPlanTests.swift:296-322`) asserts only the notification third.
Replacing the other two with constants in a scratch clone at `989ece0`:

```swift
unreadableCount: 0,
hasReadRepairs: false,
```

```
✔ Test run with 191 tests in 34 suites passed after 0.050 seconds.
```

That deletes `.unreadableRecords` and `.readRepairs` from Today for every user — the §5.2b unreadable-record surface, and the aggregate-card precedent that R4-1's own scope exception was granted against (`PROD-READINESS-2.md:147`).
The function's new doc comment states the general rule at `:77-78`: *"Each extraction that stops short of the arguments just moves that hole one frame out."* The guard was then written to the reviewer's example rather than to the function the rule describes.

**why the builder missed it.**
The remediation was scoped by the reproduction it was given (`notifications: model.notifications -> nil`) and was falsified against that same token.
A guard written from the failure it is answering, rather than from the surface it now owns, closes exactly one argument.

### 4. P3 — an existing assertion was weakened further than the locale repair required, and a stronger locale-safe form was available and works

**evidence.**
`c566ce6` replaced two equalities in `TodaySectionPlanTests.aPartialFailureNamesTheCount`:

```swift
- #expect(one.headline == "1 subscription couldn't be updated")
+ #expect(one.headline.contains(subscriptionCountText(1)))
+ #expect(one.headline.hasSuffix("couldn't be updated"))
- #expect(three.headline == "3 subscriptions couldn't be updated")
+ #expect(three.headline.contains(subscriptionCountText(3)))
```

The locale fix was necessary and finding 1 of the previous review demanded it. Dropping the equality was not.
`CoverageGapCard.headline` is `String(localized: "\(subscriptionCountText(failureCount)) couldn't be updated")` (`TodayView.swift:272-276`), so the exact-equality form is expressible without any ASCII digit. I substituted it and ran the harness:

```
en_CA                            ✔ Test run with 191 tests in 34 suites passed.
th_TH@calendar=buddhist          ✘ 1 issue    (the pre-existing DisplayFormattingTests.swift:49)
ar_SA@calendar=islamic-umalqura  ✘ 5 issues   (the documented baseline, unchanged)
```

So `#expect(one.headline == "\(subscriptionCountText(1)) couldn't be updated")` holds in all three environments and pins the whole string.
As shipped, a headline of `"1 subscription subscriptions couldn't be updated"` passes; under the assertion that was replaced it did not. `three.headline` has lost its suffix assertion entirely.
The new `one.headline != three.headline` is real added strength and is why this is P3 rather than P2.

**why the builder missed it.**
The repair was framed as "stop pinning ASCII digits", and `contains` is the reflex answer to that framing.
The available answer — interpolate the same helper into the expected string and keep the equality — needed a second step the framing did not prompt.

### 5. P3 — the widened predicate also selects the §5.3 dirty-flag branch, and the "strictly widens" paragraph does not say so

**evidence.**
`OttoStore+DataTransfer.swift:58` is `try restoreThroughMainSave(snapshot, at: instant, markingDirty: watermarks == .reconstruct)`.
So an all-tombstoned merge, which previously wrote no restore dirty flag at all, now writes one before the main save and clears it in the reconstruction's save — and acquires the §5.3 double-fault window (`:131-138`, `try? clearRestoreDirtyFlag()`) that `.keep` did not have.
`PROD-READINESS-2.md:223` accounts only for the predicate (*"The predicate **strictly widens** … the only new cases are databases holding nothing but tombstones"*), and `:237`'s "What this does NOT do" is about reach, not about what the new cases now do.

This is the second occurrence of a flagged class: `reviews/REVIEW-3.md:135` raised precisely this for the previous widening — *"The second-order effect — that the policy also selects the dirty-flag branch — is one call deep and is not visible in the diff."*

It is P3 and not P2 because the effect is benign and already covered. Round 1's remediation renamed the invariant test for the policy rather than the strategy (`RestoreDirtyFlagTests.swift:138-142`, *"Named for the POLICY, not the import strategy"*), so no test statement is stale, and the end state is still flagless. On an all-tombstoned database there is also no watermark to strand.

**why the builder missed it.**
The change is one token in an expression whose name (`reconstruct`) describes only its watermark meaning; its second consumer is a `markingDirty:` argument one call away, in a different file.

### 6. P3 — the REVIEW RANGES table gains stage 3's row and still has no stage-4 row: the fourth recurrence

**evidence.**
`PROD-READINESS-2.md:44-49` now carries rows for stages 0-3. `62b4128..989ece0`, the range this review was handed, appears nowhere.
`reviews-2/REVIEW-1.md` finding 6 raised this, `reviews-2/REVIEW-2.md` finding 5 raised it again, `reviews-2/REVIEW-3.md` finding 7 raised it a third time and argued the point that answers the obvious objection: the reviewed head is unknowable before the last commit exists, but the range **start** (`62b4128`, stage 3's reviewed head) was knowable from the first commit of this stage.
The remediation added the row for the *previous* stage and left the current one for the verdict again.

**why the builder missed it.**
The table is being treated as a record of completed reviews rather than of ranges issued, which is the same "record it later" that produced round 1's `RF-2` — the blind spot this table exists to prevent.

### 7. P3 — two live statements about the non-Gregorian baseline contradict the baseline this stage just restored

**scope note:** both sentences were shipped by `12fdcfc`, inside stage 3's range, not this one. I report them because this stage's remediation restores the count they describe and therefore re-affirms them as the standing record, and because `reviews-2/REVIEW-3.md` finding 1 corrected the *number* and left the *reasoning* in place.

**evidence.**
`PROD-READINESS-2.md:258`: *"**Calendar-caused, 2 tests.** `DisplayFormattingTests.swift:49` and `NotificationReconciliationTests.swift:170` … These fail on **any** non-Gregorian host."*
Measured at `989ece0`, `NotificationReconciliationTests.swift:170` fails only under `ar_SA`:

```
th_TH@calendar=buddhist   1 issue   ✘ DisplayFormattingTests.swift:49  "Aug 15, 2569 BE"
ja_JP@calendar=japanese   1 issue   ✘ DisplayFormattingTests.swift:49  "Aug 15, Reiwa 8"
ar_SA@calendar=islamic    5 issues  ✘ ... NotificationReconciliationTests.swift:170
                                       "FoodApp charges $15.99 on Rab. I 12."
```

Its body carries a month and a day and no year, so a calendar that agrees on month and day does not move it. The ledger's own next paragraph (`:261`) says *"1 issue under Buddhist and Japanese"*, which is the disproof of `:258` sitting three lines below it.

`CalendarEraTests.swift:34-35` carries the arithmetic version of the same error: *"`ar_SA@calendar=islamic-umalqura` — 5 issues, **the four above** plus `DisplayFormattingTests.swift:59,68,69`"*. Two tests are named above, not four, and 4 + 3 is not 5.

**why the builder missed it.**
`:170` was classified by inspecting the mechanism (`Date.FormatStyle` renders through the process calendar) rather than by reading the per-locale runs it had already produced. The mechanism is right; the blast radius was assumed from it.

### 8. P3 — the new overload inherited the old one's doc comment, leaving one function with two summaries and the other with none

**evidence.**
`TodaySectionPlan.swift:62-78` is now a single comment block. It opens with the pre-existing summary — *"Builds the input from the stores. … That is Wave 9A defect 1's shape, and round 1's R0-1 had the same one at the same call site."* — and then, with no separator, begins a second summary at `:70`: *"The whole mapping, from the model the view holds."*
It is attached to `input(model:...)`. The five-argument `input(overview:...)` it used to document (`:94-101`) now has no doc comment at all, and is the overload finding 3 shows is still the escape hatch.

**why the builder missed it.**
The new function was inserted immediately below an existing comment rather than above it, and the diff reads as a pure addition — the reattachment is invisible unless the file is re-read whole.

---

## Checked and found clean (recorded so severity is not inflated by omission)

- **SwiftData schema.** No change anywhere. `git diff --stat 7a3cf54..989ece0 -- Packages/OttoPersistence/Sources/OttoPersistence/Schema/` is empty for the **whole round-2 branch**. Grepping the stage diff for `@Model`, `VersionedSchema`, `SchemaMigrationPlan`, `@Attribute`, `@Relationship`, `MigrationStage`, `Schema(` or `ModelContainer` returns one line and it is inside `reviews-2/REVIEW-3.md`. This stage touches persistence (`RestoreIntoEmptyStoreTests.swift`) only in tests, and the domain export type only by adding a computed property — no stored field, no `Codable` surface (`OttoDataSnapshot` is not `Codable`; the wire format is `exportData`/`importedSnapshot`, untouched), so the export file format is unchanged.
- **Prohibited actions by the builder.** The stage touches nine files (`git diff --name-only 62b4128 989ece0`) and none of them is `.swiftlint.yml`, `.github/`, `project.yml`, any `Package.swift`, `PROD-READINESS.md`, anything in `reviews/`, `DECISIONS.md`, `docs/` or `README.md`. No new dependency, no new config key, no Swift language mode or SDK change. `git reflog` shows four ordinary commits with no rebase, reset, amend, cherry-pick or tag operation. `.git/FETCH_HEAD` does not exist, `refs/remotes/origin/main` is still `406a5a6`, and `git branch -a --contains 989ece0` returns only the local branch — nothing was fetched, pulled or pushed.
- **Nothing marked resolved without an artifact.** R3-1 cites `20d189a`; it exists, it is inside this range, and I falsified its guard three ways. `989ece0` replaced the placeholder `<stage-4 commit>` with the real SHA, which is the correct handling of a self-referential citation. The REVIEW RANGES row for stage 3 cites `reviews-2/REVIEW-3.md`, which `ca11f5e` adds in this same range.
- **The fix does not relocate the bug, in the direction it does cover.** For inputs that newly reconstruct, `.reconstruct` deletes every watermark row and rebuilds under the v2.5 cap `min(reconstructed, current[id] ?? reconstructed)` (`OttoStore+Watermarks.swift:82`), which can only pull a watermark earlier; the merge's resolved snapshot is a union, so nothing is tombstoned by the restore diff; `materializeEvents` dedups against live rows and non-upcoming tombstones, so nothing double-charges. The one behaviour the ledger does not mention is finding 5. The direction it does *not* cover is finding 1.
- **The changed persistence assertion was strengthened, not weakened.** `RestoreIntoEmptyStoreTests.swift:140-142` moves the fixture event from `2026-03-01` to `2026-05-01` and `:166-169` still expects `2026-03-01`. That makes the assertion discriminating where it was ambiguous, which is exactly what `reviews-2/REVIEW-3.md` finding 6 asked for, and I confirmed it fails when the event fetch's live filter is dropped. No test anywhere in the range is skipped, `.disabled(...)`-ed, deleted or removed. The only assertion loosened is finding 4.
- **The `.keep` control is not vacuous.** `RestoreIntoEmptyStoreTests.swift:109`'s `== nil` looked like it might be true by construction (nothing writes a watermark into that store). It is not: making `restore` reconstruct under both policies fails it, along with `:55` and `DataTransferTests.swift:207` — 3 issues. It genuinely detects "keep started reconstructing".
- **Guards that stay green before and after.** I broke each new guard at the line a future refactor would touch, not at a helper: the `ExportService` predicate (3 directions, above), the `input(model:)` store read (3 issues), the event fetch's live filter (2 issues), the subscription fetch (2 issues). `#expect(!buried.isEmpty)` at `ExportServiceTests.swift:166` and `#expect(!snapshot.isEmpty)` at `RestoreIntoEmptyStoreTests.swift:100` are true by construction and are declared as premises, not as guards.
- **Verification exercises the changed path where it can.** `mergeIntoAllTombstonedDatabaseReconstructsWatermarks` drives the real `ExportService.performImport` through a real file on disk, a real `exportData`/`importedSnapshot` round trip and the real `resolveImport(.merge)`, asserting the policy at the one seam a service-layer test can reach. Its store-side sibling drives the real `OttoStore.restore(_:at:watermarks:)` over real SwiftData containers. **The two halves never meet** — `OttoPersistence` does not depend on `OttoServices`, so reverting the predicate leaves the store test green (I measured: the only failure was `ExportServiceTests.swift:181`). That is the pre-existing seam boundary this repository already documents at `ExportServiceTests.swift:122-126`, and the new store test does close the specific link `reviews/REVIEW-3.md` finding 1 named (the policy argument to `restore`, rather than a direct call to `reconstructMaterializationWatermarks()`). The ledger's *"Proved against the real store, not only against the policy"* (`:235`) is fair for that claim; it is not a claim that the store test guards the predicate, and it should not be read as one.
- **Citations spot-checked.** `ExportService.performImport`'s pre-fix predicate, `OttoDataSnapshot.isEmpty` being raw-array emptiness, `completeSnapshot()` carrying tombstones (`OttoStore+DataTransfer.swift:12-30`), `min(storedWatermark ?? today, today)` at `OttoStore+BillingEvents.swift:54`, `ImportPreview.databaseIsEmpty` still reading `isEmpty` (`ExportService.swift:55`) and `SettingsView.swift:293` still gating the prompt on it, round 1 rating R3-1 P2 (`reviews/REVIEW-3.md`, *"which is why it is P2 and not P1"*), and `PROD-READINESS.md:188` recording it — all say what they are claimed to say. The stage's *own* stale-citation repairs check out too: `RestoreIntoEmptyStoreTests.swift:23`'s new pointer to `DataTransferTests`'s `replaceImportReconstructsWatermarks` is a real function at `DataTransferTests.swift:243`, and `RestoreIntoEmptyStoreTests.swift:116` is the line the R0-6 falsification actually reports. The `reviews-2/REVIEW-3.md` finding 4 class does not recur in this stage's own new text.
- **No feature smuggled.** The source changes are: one new computed property in `OttoDomain` used by exactly one production call site, one token changed in `ExportService`, one new internal overload in `TodaySectionPlan` that is argument-for-argument the code it replaced in `TodayView` (I diffed them), and comment edits. No new screen, setting, navigation, persisted state, or user-facing string. The R4-1 copy exception is not re-used — `CoverageGapCard`'s two wordings are byte-identical to stage 2's.
- **Error handling.** Nothing new is swallowed. `hasNoLiveRecords` is pure and total. `performImport` still lets `importedSnapshot`, `completeSnapshot`, `resolveImport` and `restore` throw to the caller. `completeSnapshot()` still *throws* on an unmappable record rather than skipping, so `hasNoLiveRecords` cannot be satisfied by a partial read — the same property round 1 checked for `isEmpty`. No new `try?`, `catch {}` or defaulted failure.
- **The dirty-flag invariant statement is not stale.** `RestoreDirtyFlagTests.swift:138-142` was already renamed for the policy rather than the strategy in round 1, so this stage's widening does not falsify it. The end state is still flagless under both policies and the suite passes.
- **File lengths and lint.** `TodayView.swift` 367, `TodaySectionPlan.swift` 149, `RestoreIntoEmptyStoreTests.swift` 172, `ExportServiceTests.swift` 213, `TodaySectionPlanTests.swift` 323 — all under the 400-line `file_length`. `swiftlint --strict` is clean at all three source commits, so no limit was outgrown and none was relaxed.
- **"Cannot be verified" claims.** This stage makes none of its own. The inherited CANNOT ASSESS entries (device notification daemon, Release configuration, accessibility tree) are unchanged, and the 7 simulator known issues are still the four `EmptyStateTests` accessibility assertions.
- **Severity is neither inflated nor deflated within the item.** Round 1 rated R3-1 P2 and the ledger keeps it there; N2-3 is recorded as P2 in NEXT ROUND, which is the right band even though its description is wrong (finding 1). The one claim that overstates is `:262`'s "narrower door".
- **The stderr noise is unchanged.** The `CoreData: error:` model-checksum and `deviceStateStoreUnavailable` lines appear identically with every mutation I applied and with none, and the suite passes in all of them. Pre-existing diagnostics from a deliberate migration-failure test.

## Prohibited actions by me: none, and what I did instead

- No network call of any kind. No `git ls-remote`, `git fetch` or `git pull`. Remote state was read only with `git show-ref`, `git remote -v`, `git branch -a --contains`, and the absence of `.git/FETCH_HEAD`. `git clone /Users/<user>/dev/otto <scratch>` is a local-filesystem clone.
- No physical device. One iOS Simulator run, `-scheme OttoUI-Package -destination "id=<simulator-udid>"`, from `Packages/OttoUI/` in a scratch clone.
- No edit to any repository file except this one. `git status --porcelain` in `/Users/<user>/dev/otto` is empty and `HEAD` is `989ece02904c2d7762aaa4b013c40a36de9f032e`. Every falsification and mutation was made in one of two throwaway clones under the session scratch directory, outside the repository, and reverted with `git checkout -- .` after each; I confirmed `git status --porcelain` empty in the clones afterwards.
- I created and then removed one file, `ZZReviewProbeTests.swift`, inside a scratch clone I created, with `rm -f`. Disclosed rather than concealed. Nothing I did not create was deleted, no `rm -rf` was run on any path, and nothing in `<backup-dir>` was read, moved or modified.
- The session scratch directory already contained artifacts from earlier stages of this run. I neither read them as evidence nor deleted them; every number in this document was re-derived in `rev4/`, a directory I created.
- `scripts/verify.sh` exited 0, so it wrote no `verify-*-failure.log` into the repository; I confirmed none exists.
