# REVIEW-3 - stage 3, commit range `100c508..62b4128`

**VERDICT: PASS-WITH-FINDINGS**

The range holds five commits: the stage-2 review artifact (`1f6dd2f`), stage 2's remediation (`12fdcfc`), the R0-6 fix (`db13abd`), the lint-driven file split (`8ea8162`), and a ledger bookkeeping commit (`62b4128`).

R0-6's fix is correct, minimal, and does what the ledger says it does.
I reproduced the defect and the repair end to end through the **real** merge-import path (`resolveImport(.merge)` + `restore(.keep)`), which the shipped test only approximates with a raw context write: without the fix the resurrected subscription's watermark is `nil`, with it the watermark is the anchor.
No schema change of any kind, in this range or anywhere on the round-2 branch.
No prohibited action by the builder.
Every new guard I broke died with the line it guards, including the one a future refactor would actually touch.

The findings are that the stage **regressed the run's own documented non-Gregorian baseline from 5 issues to 7, using the exact defect class the same commit had just diagnosed and routed to NEXT ROUND**, that R4-1's view wiring is still cuttable with all 189 tests green while the ledger's falsification table labels something else "**the wiring**", and that `db13abd`'s commit message claims a lint-clean state the commit does not have.

---

## Verification re-derived from scratch (nothing below is read from an artifact)

| measurement | `reviews-2/BASELINE-2.md` at `7a3cf54` | `reviews-2/REVIEW-2.md` at `100c508` | re-derived by me at `62b4128` |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 533 (246 / 113 / 174) | exit 0, 546 (248 / 113 / 185) | **exit 0**, **551** (OttoDomain **248**, OttoPersistence **114**, OttoUI **189**) |
| `swiftlint --strict` | clean | clean | **clean, 0 violations in 206 files** |
| simulator from `Packages/OttoUI/` | `** TEST SUCCEEDED **`, 101 / 65 / 20, 7 known issues | 102 / 70 / 26, 7 known issues | **`** TEST SUCCEEDED **`**, exit 0, **102 / 70 / 30**, **7 known issues** |
| `ar_SA@calendar=islamic-umalqura` harness | 5 issues | 5 issues (185 tests) | **7 issues** (189 tests) - see finding 1 |
| `th_TH@calendar=buddhist` / `ja_JP@calendar=japanese` | 1 issue | 1 issue | **1 issue** each |

The deltas reconcile exactly to the diff: OttoPersistence 113 -> 114 is `db13abd`'s R0-6 guard; OttoUI 185 -> 189 is `12fdcfc`'s two `CoverageGapCardTests` plus two `TodayInputTests`; the simulator's 26 -> 30 is the same four tests, which are in the simulator-hosted `OttoUITests` bundle.
The 7 known issues are unchanged and are the same four `EmptyStateTests` accessibility assertions at `:211`, `:235`, `:254`, `:295`.

### R0-6 falsified at the fix line, and the defect reproduced through the real path

Reverting `OttoStore+Watermarks.swift:57` (`let subscriptions = try modelContext.fetch(FetchDescriptor<StoredSubscription>())`) back to its predicate form, in a scratch clone at `62b4128`:

```
✘ DataTransferTests.swift:282:13   fresh.materializationWatermark(forSubscription: fixtureUUID(4))
✘ RestoreIntoEmptyStoreTests.swift:108:9  "⛔ a subscription tombstoned at reconstruct time and
                                           resurrected later still has a watermark"
✘ Test run with 114 tests in 23 suites failed after 1.440 seconds with 2 issues.
```

Exactly 2 issues, both watermark assertions and nothing else, as the ledger claims.

I did not stop at the shipped guard.
The shipped guard resurrects the subscription by writing `record.deletedAt = nil` on a raw `ModelContext`, under a comment that says *"Resurrection, exactly as a merge import performs it"*.
I wrote a throwaway probe that drives the real path instead - export the live copy with a newer `updatedAt`, `deleteSubscription`, `reconstructMaterializationWatermarks()`, then `resolveImport(strategy: .merge)` and `restore(_:at:watermarks: .keep)` - and deleted it afterwards:

```
with the fix:      PROBE live subscriptions after merge: 1
                   PROBE watermark after resurrection: Optional(2026-03-01)   ✔
fix reverted:      PROBE live subscriptions after merge: 1
                   PROBE watermark after resurrection: nil                    ✘
```

So R0-6 is a real defect on the real path and the fix really closes it.
The mechanism the ledger cites also checks out: `ImportResolution.swift`'s `merge` takes the incoming record whole when `record.updatedAt > existing.updatedAt` and counts the `(false, true)` transition as `added`, which is `deletedAt` being cleared; `OttoStore+BillingEvents.swift:54` is literally `let windowStart = min(storedWatermark ?? today, today)`.

### The other new guards each die with their own line

```
TodaySectionPlan.swift:86  lastPassFailed: notifications?... -> false
   ✘ TodaySectionPlanTests.swift:254 (input(store)...).lastPassFailed → false
   ✘ TodaySectionPlanTests.swift:255 (TodaySection.plan(input(store)) → [needsAction]).contains(.coverageGap)

TodayView.swift headline ternary swapped
   ✘ TodaySectionPlanTests.swift:183 (card.headline → "0 subscriptions couldn't be updated")
   ✘ TodaySectionPlanTests.swift:185 !((card.headline → "0 subscriptions couldn't be updated").contains("0"))
   ✘ :192, :194 both count wordings

TodayView.swift detail ternary swapped ON ITS OWN
   ✘ TodaySectionPlanTests.swift:186 and :197
```

The wording swap prints the exact sentence the item exists to prevent, so the failure message is the finding.
The `detail` branch is guarded independently of `headline`, which the ledger does not claim but which is the stronger property.

---

## Findings

### 1. P2 - the stage regressed the non-Gregorian baseline from 5 issues to 7, with the defect class its own commit had just diagnosed

**severity:** P2, not P1: both new failures are over-specified test assertions, not product defects, and the Gregorian host and CI stay green.
It is P2 rather than P3 because the run *created* the non-Gregorian harness as an evidence surface, *documented* its baseline in shipped source as the thing a future reader must compare against, and then made that baseline worse in the same commit that corrected its description - while leaving the old number in place in two files.

**evidence.**
At `62b4128`, `ar_SA@calendar=islamic-umalqura` through the harness `reviews-2/BASELINE-2.md:49-55` documents:

```
✘ TodaySectionPlanTests.swift:192:9: (one.headline → "١ subscription couldn't be updated")
                                     == "1 subscription couldn't be updated"
✘ TodaySectionPlanTests.swift:194:9: (three.headline → "٣ subscriptions couldn't be updated")
                                     == "3 subscriptions couldn't be updated"
✘ Test run with 189 tests in 34 suites failed after 0.049 seconds with 7 issues.
```

At `100c508`, the same command on the same host: `✘ Test run with 185 tests in 32 suites failed after 0.051 seconds with 5 issues.`
The two extra issues are `CoverageGapCardTests.aPartialFailureNamesTheCount`, added by `12fdcfc` - this stage.
`th_TH` and `ja_JP` are still 1 issue each, so only the `ar_SA` count moved.

The count is now wrong in two places, both shipped by this stage or restated by it:

- `Packages/OttoUI/Tests/OttoStoresTests/CalendarEraTests.swift:34`: *"`ar_SA@calendar=islamic-umalqura` - 5 issues, the four above plus `DisplayFormattingTests.swift:59,68,69`"*, under a heading that calls them *"PRE-EXISTING failures, measured at `7a3cf54` and unchanged by F1"* and instructs the reader to *"Read the named tests, not the exit code"*.
  Two of the seven are neither pre-existing nor named.
- `PROD-READINESS-2.md:228`: *"the per-host baseline is 1 issue under Buddhist and Japanese, 5 under `ar_SA`, which is what this ledger and `CalendarEraTests.swift` record."*

The mechanism is identical to the one `12fdcfc` itself wrote down four paragraphs earlier at `PROD-READINESS-2.md:226`: *"they render Arabic-Indic numerals under `ar_SA` ... through `String(localized:)` and `AttributedString(localized:)`, neither of which touches a date."*
`CoverageGapCard.headline` interpolates `subscriptionCountText(failureCount)` through `String(localized:)`, which is the same construction as `DisplayFormattingTests.swift:68,69` - the very tests N2-1 names.

**why the builder missed it.**
The commit's verification was declared as *"OttoUI 185 -> 189 host, swiftlint --strict clean"* and stopped there.
The non-Gregorian harness was treated as F1's instrument rather than as a standing baseline, so a stage whose subject was R4-1's copy never ran it - even though the same commit was rewriting the record of what that harness prints, and even though the new assertions pin exactly the string shape the rewrite was about.

### 2. P2 - R4-1's view wiring is still cuttable with every test green, and the ledger still labels something else "the wiring"

**severity:** P2 for the same reason `reviews-2/REVIEW-2.md` finding 1 was P2 - the code at HEAD is correct and the card does appear.
What is missing is any artifact that would notice if the whole notification half of Today stopped appearing, while the record asserts that seam is now falsified.

**evidence.**
In a scratch clone at `62b4128`, replacing `TodayView.swift:49`'s `notifications: model.notifications` with `notifications: nil` - a one-token edit that compiles, because the parameter is `NotificationStatusStore?`:

```
✔ Test run with 189 tests in 34 suites passed after 0.056 seconds.
```

That cut removes `permission`, `scheduleOutcome` and `lastPassFailed` from `TodaySection.Input` in one stroke: no permission banner for a denied user, no coverage sentence for a healthy one, and no coverage-gap card for a failed pass.
It is strictly larger than the cut `reviews-2/REVIEW-2.md` finding 1 made (`lastPassFailed:` alone), and it survives the remediation intact.
`grep -rn "TodayView" Packages/OttoUI/Tests/ Otto/` returns one match and it is a comment, so nothing renders or constructs `TodayView`.

Against this, `PROD-READINESS-2.md:164` lists as a falsification row: *"`TodaySection.input`'s read of the store (**the wiring**)"*.
That row is real and I reproduced it - but `TodaySection.input` is a static factory the test calls directly, which is the helper-shaped seam again; the wiring is `TodayView.overviewList`'s call to it.
`PROD-READINESS-2.md:169` then scopes the residual to rendering only: *"`coverageGapSection`'s one-line body can be replaced with `EmptyView()` ... the two consequential seams either side of it (the input mapping and the card's own copy) are guarded."*
The input mapping is guarded; the view's *feed* of that mapping is not, and it is on the same side of the seam the sentence declares closed.

**why the builder missed it.**
The remediation moved the untestable code one call frame outward and stopped where the test could reach.
Extracting `Input` left the mapping behind on a `View`; extracting `input` left the *arguments* behind on the same `View`.
Each extraction closes the shape it was pointed at and leaves the next one, and the record was written from the perspective of what the new test can now assert rather than from what a future edit can still delete.

### 3. P3 - `db13abd`'s commit message claims "swiftlint --strict clean" and that commit is not

**evidence.**
`db13abd`'s message ends: *"OttoPersistence 113 -> 114, swiftlint --strict clean."*
Checking out `db13abd` in a scratch clone:

```
DataTransferTests.swift:403:1: error: File Length Violation: File should contain 400 lines
  or less: currently contains 403 (file_length)
OttoStore+DataTransfer.swift:403:1: error: File Length Violation: File should contain 400 lines
  or less: currently contains 403 (file_length)
```

`git show db13abd:<each file> | wc -l` confirms 403 and 403 independently.
The repair in `8ea8162` is real, is disclosed in that commit's own message, and is recorded at `PROD-READINESS-2.md:202` - but the ledger records the *regression* and not the *false claim*, in a document that already carries a dedicated section for this exact species (`PROD-READINESS-2.md:119`, "Corrections to this stage's own commit message").
Since commit messages cannot be amended, this is the ledger's job and it is the one correction it did not make.

**why the builder missed it.**
The lint check was run against the working tree before the final split rather than against the commit, and once the split landed clean the intermediate state stopped being interesting.
The ledger then framed the episode as "caught and repaired inside the stage", which is a true and creditable framing that happens to make the false sentence invisible.

### 4. P3 - the R0-6 falsification block and the "Reconfirmed at HEAD" paragraph cite a file layout that the same stage deleted

**evidence.**
`PROD-READINESS-2.md:196` cites the R0-6 guard's failure at `DataTransferTests.swift:397`.
At `62b4128` that file is 300 lines; the test lives at `RestoreIntoEmptyStoreTests.swift:108`, which is where my own revert run reports it.
`PROD-READINESS-2.md:183` opens *"**Reconfirmed at HEAD.** `OttoStore+DataTransfer.swift` fetches subscriptions with `deletedAt == nil` ..."*, but `reconstructWatermarksNow` is not in that file at HEAD - `8ea8162` moved it to `OttoStore+Watermarks.swift`, two commits before the ledger commit that shipped this paragraph.
The moved suite carries the same problem in source: `RestoreIntoEmptyStoreTests.swift:22` says *"The sibling test above proves what `reconstructMaterializationWatermarks()` computes"*, and there is no sibling test above it in that file any more.

The evidence is not wrong - the numbers were true when measured - it was measured before the split and not re-derived after it.
This is `reviews-2/REVIEW-1.md` finding 5 and `reviews-2/REVIEW-2.md` finding 4, recurring a third time, one paragraph below `PROD-READINESS-2.md:175`, where the builder writes that this defect class recurred "in the document written to correct it".

**why the builder missed it.**
The falsification was performed against `db13abd`, the ledger prose was drafted against `db13abd`, and `8ea8162` was treated as a cosmetic lint repair rather than as a change that invalidates every line citation written before it.

### 5. P3 - R0-6's own round-1 evidence names three filters; one was removed and the ledger does not say the other two remain

**evidence.**
`reviews/REVIEW-0.md:195-200`, the finding R0-6 inherits, is explicit: *"`:222-231` re-creates a row only for a subscription that survives three filters: the fetch at `:203-205` excludes tombstoned subscriptions, and `:223-225` requires a non-nil `id` and a non-nil `latestBySubscription[id] ?? cycleStartDay`, otherwise `continue` leaves no row at all."*
The heading itself is plural: *"its own nil-watermark **holes**"*.
`PROD-READINESS.md:75` cites both filter sites in the same cell.

`OttoStore+Watermarks.swift:75-77` still carries the other two:

```swift
guard let id = subscription.id,
      let reconstructed = latestBySubscription[id] ?? subscription.cycleStartDay
else { continue }
```

`PROD-READINESS-2.md:185` describes the change as *"One line: the fetch drops its predicate"* and says nothing about them, while the work-list row is flipped to **RESOLVED**.
ITEM 1 and ITEM 2 both carry explicit "what this does not do" sections; ITEM 3 has none.

I chased the residual and it is **inert**, which is why this is P3 and not P2: a record with a nil `id` or a nil `cycleStartDay` cannot map to a domain `Subscription` at all - `SubscriptionMapping.swift:41,49` route both through `require(...)` / `CalendarDay.stored(...)`, and `StorageShapes.swift:24-30` throws `MappingError` on nil before `Subscription.readingRepaired` is ever reached - so such a record is skipped by `mapSkippingFailures`, counted in `unreadableCount`, and can never reach `materializeEvents`.
For every subscription that *can* materialize, the fix guarantees a row.
That is the completeness statement the item should have made, and the reader has to derive it.

**why the builder missed it.**
The work-list row (`PROD-READINESS-2.md:32`) paraphrases R0-6 down to its tombstone half, and the stage was worked from that paraphrase rather than from `reviews/REVIEW-0.md`'s three-filter evidence.
The paraphrase is accurate about the reachable consequence, which is why it did not feel lossy.

### 6. P3 - both tombstoned-subscription watermark assertions are satisfied by two different derivations, so the design decision the ledger highlights has no guard

**evidence.**
`PROD-READINESS-2.md:185` makes a deliberate design claim: *"The **event** fetch still filters to live rows, so a tombstoned subscription falls back to its anchor rather than inheriting a dead ledger's progress."*
In `DataTransferTests.swift`'s `seedRichStore`, fixture 4 is `cycleStartDay: day(2026, 3, 1)` (`:33`) with its single event at `expectedDate: day(2026, 3, 1)` (`:35`).
In `RestoreIntoEmptyStoreTests.swift:82,85`, the new test's subscription is anchored `2026-03-01` and its only event is dated `2026-03-01`.
Both assertions expect `2026-03-01`, which is simultaneously the anchor and the dead ledger row, so neither can tell the two derivations apart.

Dropping the `deletedAt == nil` predicate from the **event** fetch in a scratch clone confirms it:

```
✘ DataTransferTests.swift:262:13   (fixture 1, a LIVE subscription)
✘ Test run with 114 tests in 23 suites failed after 1.407 seconds with 1 issue.
```

One issue, from the live-subscription case only.
Neither tombstoned assertion moves.
The live-only rule is therefore guarded in general and unguarded for the case this item is about.

**why the builder missed it.**
Fixture 4 was inherited with the anchor and the event already on the same date, and the new test was written in its image; the assertion was chosen for the value it should print rather than for the values it must exclude.

### 7. P3 - the REVIEW RANGES table still has no row for this stage, which is the third recurrence

**evidence.**
`PROD-READINESS-2.md:44-48` carries rows for stages 0, 1 and 2 only.
`100c508..62b4128`, the range this review was handed, appears nowhere.
`reviews-2/REVIEW-1.md` finding 6 raised this, `reviews-2/REVIEW-2.md` finding 5 raised it again, `12fdcfc` added stage 2's row in remediation, and `62b4128` - the ledger commit that closes this stage - did not add stage 3's.
The reviewed head is genuinely unknowable before the last commit exists, but the range **start** (`100c508`, stage 2's reviewed head) was knowable throughout, which is the argument `reviews-2/REVIEW-1.md:196` already made.

**why the builder missed it.**
The row is being held for the verdict for the third time, which is the same "record it later" that produced round 1's `RF-2`.

---

## Checked and found clean

- **SwiftData schema.** No change anywhere. `git diff --stat 7a3cf54..62b4128 -- Packages/OttoPersistence/Sources/OttoPersistence/Schema/` is empty for the **whole round-2 branch**, not just this range. No `@Model`, `VersionedSchema`, `SchemaMigrationPlan`, `@Attribute`, `@Relationship`, `MigrationStage` or `Schema(...)` line is added or removed. `StoredMaterializationWatermark`, `OttoSchemaV3`, `OttoMigrationPlan` and `OttoContainerFactory` are byte-identical. The stage's persistence change is a fetch predicate and a file move, both in `Sources/.../Store/`.
- **Prohibited actions by the builder.** `.swiftlint.yml`, `.github/`, `project.yml`, every `Package.swift`, `PROD-READINESS.md`, everything in `reviews/`, `DECISIONS.md`, `docs/` and `README.md` are untouched across `7a3cf54..62b4128`. No new dependency, no new config key, no Swift language mode or SDK change. `git reflog` shows five ordinary commits with no rebase, reset, amend or tag operation. `.git/FETCH_HEAD` does not exist, `refs/remotes/origin/main` is still `406a5a6` (unchanged from what `reviews-2/REVIEW-2.md` recorded), and `git branch -a --contains 62b4128` returns only the local branch - nothing was fetched, pulled or pushed.
- **The file split is authorized and behaviour-preserving.** I reconstructed the pre-split block from `12fdcfc` and diffed it against `OttoStore+Watermarks.swift` with comments and blank lines stripped. The only differences are: the imports and `extension OttoStore {` wrapper, the one-line R0-6 fix, and `markRestoreDirty` going `private` -> internal. Nothing else moved, reordered or changed. The visibility widening is necessary (`private` is file-scoped and `restoreThroughMainSave` in the other file calls it), is the minimum widening available, and is disclosed in both the commit message and `PROD-READINESS-2.md:202`. `reconstructMaterializationWatermarks()` still witnesses `DataTransferRepository` from a plain extension in the same module, which compiles and is semantically identical. The test split moves a suite that already lived in its own extension; its nesting under `SerializedPersistenceTests` and therefore its `.serialized` trait are preserved, and the suite count moved 22 -> 23 with the same 114 tests.
- **The split was necessary, not a preference.** `.swiftlint.yml` declares no `file_length` override, so SwiftLint's default 400-line warning applies and `--strict` promotes it; I confirmed the pre-split files violate it at `db13abd` and that the rule file is untouched. The scope constraint's "restructure or split a file deliberately" is exactly what was done.
- **The fix does not relocate a bug.** I asked what the new behaviour does to cases R0-6 did not name. A tombstoned subscription now gets a row at `min(anchor, previously-stored)`, which can only pull a watermark *earlier*; the v2.5 cap is untouched, so nothing can advance. Downstream, `materializeEvents` dedups against live rows **and** non-upcoming tombstones (`OttoStore+BillingEvents.swift:99-103`), so a resurrected subscription re-materialising from its anchor cannot duplicate a confirmed charge. `materializeEvents` returns early on `subscription.deletedAt != nil` before it ever reads the watermark (`:38`), `subscriptions()` and `subscription(withID:)` are live-only, and `NotificationScheduler` iterates live subscriptions - so the ledger's "never read while it stays tombstoned" holds. The only other reader is `initializeMaterializationWatermark`'s nil-guard, reachable only from `SubscriptionsStore.save`'s new-entry branch, which is gated on `subscription(withID:)` returning nil and cannot be reached with an id that exists only as a tombstone. The stated cost - one device-state row per tombstoned subscription, permanently, since hard deletes happen nowhere - is real, disclosed, and proportionate.
- **The changed assertion was strengthened, not weakened.** Exactly one existing assertion changed: `DataTransferTests.swift:283` went from `== nil` to `== day(2026, 3, 1)`. That pins a value where an absence stood, and the absence was the defect. No test was skipped, disabled, `.disabled(...)`-ed, deleted or loosened anywhere in the range; the only other test-file edits are moves, a doc comment, and additions.
- **The recorded invalid falsification is honest and reproduces.** `PROD-READINESS-2.md:200` says a first attempt patched `completeSnapshot`'s fetch by mistake. I reproduced it: `danglingReference(entity: "billingEvent ...000103", subscriptionID: ...000004)` at `DataTransferTests.swift:86` and `:178`, plus the tombstone-snapshot assertions at `:120` and `EpisodeStoreTests.swift:80` - 4 issues, exactly the shape described. Recording a failed attempt rather than hiding it is the right behaviour and it checks out.
- **The `CoreData: error:` stderr is pre-existing.** I ran the persistence suite at `7a3cf54` and got the same 9 lines - the model-checksum warning, the `MigrationError.deviceStateStoreUnavailable` block, and the persistent-history truncation notice - with the suite passing. They come from a deliberate migration-failure test. Not a regression, and the ledger's claim at `PROD-READINESS-2.md:204` is accurate.
- **Error handling.** Nothing new is swallowed. `markRestoreDirty` still rolls back and rethrows, `commitRestore`'s `try? clearRestoreDirtyFlag()` is pre-existing and documented as the §5.3 double fault, `reconstructWatermarksNow` still saves only under `hasChanges` and still throws. The R0-6 change adds no `try?`, no `catch {}`, no default value that masks a failure.
- **No feature smuggled.** The only source changes outside the one-line fix are: `TodaySection.input` (an extraction of code that was already in `TodayView.overviewList`, argument-for-argument identical - I diffed them), `CoverageGapCard.headline`/`.detail` losing `private` (module-internal, no public API change, required by `reviews-2/REVIEW-2.md` finding 2), `markRestoreDirty` losing `private`, and comment edits. No new screen, setting, navigation, persistence, or user-facing string. The R4-1 copy exception is not re-used: the two wordings are the ones stage 2 already shipped.
- **Guards that stay green before and after.** I broke each new guard at the line a future refactor would touch, not at a helper. `TodaySectionPlan.swift:86` -> 2 issues, both wording ternaries -> 4 and 2 issues respectively, `OttoStore+Watermarks.swift:60` -> 2 issues. One assertion is inert by construction and is worth naming: `TodaySectionPlanTests.swift:196` (`!three.headline.contains("^[")`) pins Wave 10 defect I, was already true before this stage, and guards nothing this stage changed - it is an extra, not a false guard. `TodaySectionPlanTests.swift:187` (`!input(store).lastPassFailed` before any pass) is true from the property's default, but it is the negative control that distinguishes "no pass yet" from "failed", and the assertions after it are the load-bearing ones.
- **Assertions already true for an unrelated reason.** Checked all of them. `input(store).permission == .authorized` is not free - the store's `permission` defaults to `.notDetermined` and only `apply` sets it. `plan(...).contains(.coverage)` requires both the permission gate and `canClaimCoverage`. The one real instance is finding 6. `card.headline == "Reminders couldn't be updated"` and `!headline.contains("0")` both flip on the swap, so neither is tautological.
- **Verification exercises the changed path.** The R0-6 guard calls the public `reconstructMaterializationWatermarks()` and reads back through `materializationWatermark(forSubscription:)` on a second `OttoStore` over the same containers, which is the production composition. `TodayInputTests` drives a real `NotificationStatusStore` through `reschedule()` with a throwing scheduler, and the fake reaches the production code through `ReminderScheduling`'s `trigger:`-tagged extension in `OttoLog.swift:80-92`, not around it.
- **Nothing marked resolved without an artifact.** R0-6 cites `db13abd` + `8ea8162`; both exist, both are inside this range, and I falsified a guard from `db13abd` and verified `8ea8162` is a pure move.
- **Severity is neither inflated nor deflated.** Round 1 rated R0-6 P2 and prescribed *"Rebuild for resurrectable subscriptions too"* (`PROD-READINESS.md:75`); the fix is exactly that and the terminal state is not overstated. `PROD-READINESS-2.md:187`'s claim that round 1 left `Packages/OttoPersistence/Sources/` untouched is true - `git log 406a5a6..7a3cf54 --name-only` over that path is empty.
- **Citations spot-checked.** `OttoStore+BillingEvents.swift:54`, `ImportResolution`'s resurrection branch, the v2.5 cap expression, `StoredMaterializationWatermark` being unchanged, the 456-line reconstruction of the unsplit `TodayView.swift` (369 + 97 - 10 header/import lines = **456**, re-derived at `100c508`), and `8ea8162`'s "206 files" (`swiftlint --strict` at HEAD: *"Found 0 violations, 0 serious in 206 files"*) all say what they are claimed to say. The stale ones are finding 4.
- **"Cannot be verified" claims.** This stage makes none of its own. The inherited ones in CANNOT ASSESS (device notification daemon, Release configuration, accessibility tree) are unchanged, and I confirmed the accessibility one independently: all 7 simulator known issues are `labels.contains` / activation failures inside `EmptyStateTests`.
- **R3-1 is not made worse.** `ExportService.swift:55,90` (`current.isEmpty`, item 4 and still pending) is untouched, and R0-6's fix slightly mitigates it - after any reconstruction, an all-tombstoned database now has anchor watermarks rather than none.

## Prohibited actions by me: none, and what I did instead

- No network call of any kind. No `git ls-remote`, `git fetch` or `git pull`. Remote state was read only with `git show-ref`, `git remote -v`, `git branch -a --contains`, and the absence of `.git/FETCH_HEAD`. `git clone /Users/<user>/dev/otto <scratch>` is a local-filesystem clone.
- No physical device. Two iOS Simulator runs: one failed invocation with the wrong scheme name (`-scheme OttoUI`, which exits with "not configured for the test action" and runs nothing), then the correct `-scheme OttoUI-Package -destination "id=<simulator-udid>"` from `Packages/OttoUI/` in a scratch clone.
- No edit to any repository file except this one; `git status --porcelain` in `/Users/<user>/dev/otto` is empty and `HEAD` is `62b41281545a118e5d8271961f6ce9412589ff49`. Every falsification edit was made in one of two throwaway clones under the session scratch directory, outside the repository, each reset with `git checkout -- .` after use.
- I created and then removed one file, `ZZProbeTests.swift`, inside a scratch clone I created, with `rm -f`. Disclosed rather than concealed. Nothing I did not create was deleted, no `rm -rf` was run on any path, and nothing in `<backup-dir>` was read, moved or modified.
- `scripts/verify.sh` exited 0, so it wrote no `verify-*-failure.log` into the repository; I confirmed none exists.
