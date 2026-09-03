**VERDICT: PASS-WITH-FINDINGS**

Adversarial review of stage 5, range `989ece0..5d8ed6a`, ledger `PROD-READINESS-2.md`.
Nothing below is read from the builder's account; every number is re-derived in a scratch clone outside the repository.

The R0-4 fix itself is real, correct, exercised end to end, and falsifiable in both directions exactly as claimed.
The defects are in the commit-level record: **the stage's first commit `d00c086` does not compile**, its message states a test count that cannot have been measured there, and it is the sole artifact for two remediations whose ledger rows do not name it.
Two coverage claims also overstate what was pinned.

---

## Verification re-derived from scratch

| measurement | ledger / baseline says | re-derived here | result |
|---|---|---|---|
| `scripts/verify.sh` at `5d8ed6a` | (no per-stage figure recorded) | exit 0 - OttoDomain **251**, OttoPersistence **118**, OttoUI **191**, total **560** | ✅ green |
| `swiftlint --strict` at HEAD | `0b76d65`: "clean across 208 files" | `Found 0 violations, 0 serious in 208 files`, exit 0 | ✅ exact |
| same at `989ece0` (stage-4 head) | REVIEW-4 measured 114/190 at `c566ce6` | OttoDomain **248**, OttoPersistence **115**, OttoUI **191** | ✅ deltas reconcile |
| simulator from `Packages/OttoUI/` at HEAD | baseline 101/65/20, 7 known issues | exit 0, `** TEST SUCCEEDED **`, **103 / 70 / 31**, **7 known issues** | ✅ no regression |
| same at `989ece0` | — | **103 / 70 / 31**, **7 known issues**, `** TEST SUCCEEDED **` | ✅ **this stage changed nothing** |
| non-Gregorian harness | 1 / 1 / 5 | **1 / 1 / 5** at HEAD **and** at `989ece0` | ✅ **baseline unchanged by this stage** |
| OttoPersistence suite duration | "~1.5 s to ~7 s" | `989ece0`: 1.392 / 1.405 / 1.414 s. HEAD: 6.275 - 9.415 s over 6 runs | ✅ fair |

The `+3 / +3 / 0` package delta reconciles exactly: 3 new `LiveSubscriptionPredicateTests`, 3 new `MappingLogPrivacyTests`, and the OttoUI edits add assertions to existing tests rather than tests.

### The locale baseline, re-measured on both sides

Harness per `reviews-2/BASELINE-2.md`: `swiftpm-testing-helper` against `OttoUIPackageTests`, `DYLD_FRAMEWORK_PATH` set, `-AppleLocale <loc>`.

```
5d8ed6a  th_TH@calendar=buddhist        1 issue   DisplayFormattingTests.swift:49
5d8ed6a  ja_JP@calendar=japanese        1 issue   DisplayFormattingTests.swift:49
5d8ed6a  ar_SA@calendar=islamic-umalqura 5 issues DisplayFormattingTests.swift:49,59,68,69
                                                  NotificationReconciliationTests.swift:170
989ece0  identical on all three
```

**This stage did not change the per-locale baseline**, and the corrected N2-1 entry is now right on the point REVIEW-4 finding 7 disputed: `NotificationReconciliationTests.swift:170` moves under `ar_SA` alone, not under any non-Gregorian host.
The stage's own new exact-equality assertion in `TodaySectionPlanTests` (`one.headline == "\(subscriptionCountText(1)) couldn't be updated"`) appears in no locale's issue list, so REVIEW-4 finding 4's repair is locale-safe as claimed and is a strengthening, not a weakening.

### R0-4 falsified in both directions, plus two the ledger does not record

| what I broke | result |
|---|---|
| `OttoStore.swift:122` back to `String(describing: error)` | 2 issues, `MappingLogPrivacyTests.swift:83` and `:89`; emitted line is literally `Skipping unmappable record: <private>` |
| `logSummary` made to interpolate the value again | 3 issues, `:30`, `:37`, `:88`; emitted line is `Skipping unmappable record: StoredSubscription.cycleStartDay holds an invalid value "20260230"` in plaintext |
| the emission deleted outright, full suite | 2 issues, `:82` and `:83` |
| **`CancellationEpisodeMapping.swift:184` back to `String(describing: error)`** | **`Test run with 118 tests in 24 suites passed`** - see finding 3 |

The first two reproduce the ledger's table exactly, including the pre-fix `<private>` rendering the ledger asserts.

### R3-1 and R4-1 falsified

| what I broke | result | ledger row |
|---|---|---|
| `current.hasNoLiveSubscriptions` back to `current.isEmpty` | `ExportServiceTests.swift:196` | matches |
| predicate pinned `true` | `ExportServiceTests.swift:113` **and `ExportImportTests.swift:47`** | ledger names only the first |
| predicate forced `false` | `ExportServiceTests.swift:141`, `:182`, `:196`, `ExportImportTests.swift:16`, `:34` | substance matches; symbol name stale, finding 6 |
| `unreadableCount: model…` → `0` | `TodaySectionPlanTests.swift:340`, `:342` | matches |
| `hasReadRepairs: !model…` → `false` | `:341`, `:343` | matches |
| `notifications: model.notifications` → `nil` | `:322`, `:323`, `:324` | matches |

**"All three model reads are asserted now" is true.**
I first appeared to falsify it and the apparent failure was mine: the doc comment above the function contains the literal string `notifications: model.notifications`, and a first-occurrence replacement edits the comment. Recorded because a reviewer's own bad falsification is the same defect class as a builder's.

---

## Findings

### 1. P2 - `d00c086` does not compile, and its message reports a test count that cannot have been measured there

**evidence.**

```
$ git checkout d00c086 && swift build --package-path Packages/OttoPersistence --build-tests
RestoreIntoEmptyStoreTests.swift:101:30: error: value of type 'OttoDataSnapshot'
  has no member 'hasNoLiveRecords'
BUILD EXIT=1

$ swift test --package-path Packages/OttoPersistence
error: fatalError
```

`d00c086` renames `hasNoLiveRecords` to `hasNoLiveSubscriptions` in `OttoDataSnapshot.swift` and updates the OttoDomain and OttoServices call sites, but leaves `Packages/OttoPersistence/Tests/OttoPersistenceTests/RestoreIntoEmptyStoreTests.swift:101` on the old name.
That one-line update ships two commits later, inside `0b76d65`, whose subject is the unrelated R0-4 log fix.

Its commit message ends:

> `OttoDomain 248 -> 251, OttoPersistence 115, OttoUI 191, swiftlint --strict clean across 207 files.`

I measured at `d00c086`: OttoDomain **251** ✅, OttoUI **191** ✅, `swiftlint --strict` exit 0 ✅, OttoPersistence **does not build** ❌.
"OttoPersistence 115" is unreproducible at the commit that states it; 115 is the count at `989ece0`, its grandparent.

**why this matters beyond tidiness.** `scripts/verify.sh` exists because "Wave 4's committed HEAD did not compile while the local tree passed" (its own header). CI's `persistence-tests` job runs `swift test --package-path Packages/OttoPersistence` on every push, and `docs/next-wave.md` records the standing consequence that **CI, not `verify.sh`, is the gate**. `d00c086` fails both. It is also a bisect landmine on the exact file this run keeps returning to.

**why the builder missed it.** The two halves of the rename live in different packages, and OttoPersistence's tests are the only consumer of the old name outside the packages the commit touched. The commit was split by *topic* (predicate / log) rather than by *what compiles*, and the numbers in the message were carried over from a working tree that already had both halves. This is `reviews-2/REVIEW-3.md` finding 3's class - a commit message claiming a state the commit does not have - recurring one stage after REVIEW-4 recorded that it had not.

### 2. P2 - R3-1 is marked RESOLVED against an artifact that contains the predicate REVIEW-4 rejected, and the commit that actually fixed it is recorded nowhere

**evidence.** `PROD-READINESS-2.md:33`:

> `| 4 | **R3-1** | … | **RESOLVED** — 20d189a |`

and `:227` `**RESOLVED**, 20d189a.` But:

```
$ git show 20d189a:Packages/OttoDomain/Sources/OttoDomain/Export/OttoDataSnapshot.swift
    public var hasNoLiveRecords: Bool {
        !subscriptions.contains { $0.deletedAt == nil }
            && !paymentMethods.contains { $0.deletedAt == nil }
            && … three more conjuncts
```

That is the five-conjunct form `reviews-2/REVIEW-4.md` finding 1 showed **does not fire on the state a user actually reaches**.
The shipped one-conjunct predicate is in `d00c086`, which appears in no cell of the ledger.

The same commit is R4-1's fourth artifact - it is where "all three model reads are asserted" was implemented - and `PROD-READINESS-2.md:31` lists `eb4a13b` + `12fdcfc` + `c566ce6` and stops. That row was **rewritten by `d00c086` itself**, so the commit updated the list of R4-1's artifacts and omitted itself from it.

**why the builder missed it.** `989ece0` ("Record the R3-1 commit SHA in the ledger") closed the bookkeeping for R3-1 before the review that reopened it. When `d00c086` reopened the item it rewrote the ITEM 4 *prose* thoroughly and never went back to the two terminal-state cells, because those had already been "done". The run's own `RF-2` lesson - a record kept as a log of completed things rather than of things issued - applied to review ranges and was not applied to artifact SHAs.

### 3. P3 - one of the two changed call sites has no executable guard, and "pin it from both ends" reads as if both were pinned

**evidence.** `PROD-READINESS-2.md:259`: *"Both call sites take it: `OttoStore.mapSkippingFailures` and `CancellationEpisodeMapping.storedNoteAnywhere`"*, then `:274`: *"Together those pin it from both ends."*

Reverting the second call site alone:

```
CancellationEpisodeMapping.swift:184 -> mappingLogger.error("… \(String(describing: error))")
✔ Test run with 118 tests in 24 suites passed
```

Both falsification rows in the ledger's table exercise `OttoStore.swift:122` only. `storedNoteAnywhere`'s catch fires only when a SwiftData `context.fetch` throws, which no test forces, and `EvidenceNoteReparentTests` does not reach it.

**severity P3, not higher.** The error caught there can never be a `MappingError` - it is a `context.fetch` failure over `#Predicate { $0.id == noteID }` - so `mappingLogSummary` always returns a type name and the privacy exposure at that site was theoretical. The claim is what overstates, not the code.

**why the builder missed it.** The falsification was written against the site the finding names (`OttoStore.swift:122`, cited in `PROD-READINESS.md:113`). The second site was fixed for consistency and inherited the first site's evidence sentence. It is the same shape as this run's own item 7, `R5-2`: a log line with no executable guard.

### 4. P3 - the stated cause of the earlier flake is false; the window silently contains other tests' lines

**evidence.** `PROD-READINESS-2.md:276` and `MappingLogPrivacyTests.swift:72-74` both say the first version was flaky because *"the log is process-wide and other suites run concurrently, so `first` picked up whichever test happened to skip a record at the same moment."*

The OttoPersistence target does not run suites concurrently. `TestSupport.swift:38-39` declares `@Suite(.serialized) struct SerializedPersistenceTests {}` and every suite in the target is an `extension` of it, including this one at `MappingLogPrivacyTests.swift:19`. In a full-suite log every `◇ Test … started` is immediately followed by its own `✔ … passed`, with no interleaving anywhere.

The real mechanism is that `OSLogStore.position(date:)` is approximate. Instrumented in a scratch clone:

```
PROBE since=2026-08-11 06:24:17 +0000
      earliestInWindow=2026-08-11 06:24:17 +0000
      reachBackSeconds=0.0812  count=6
PROBE window lines=6 :: ["… StoredSubscription.status is missing",
  "… StoredSubscription.status is missing", "… StoredSubscription.status is missing",
  "… StoredBillingEvent.expectedDate is missing", "… StoredTrialTerm.lengthDays is missing",
  "… StoredSubscription.cycleStartDay holds an invalid value"]
```

The window reaches ~81 ms behind `since` and contains **six** skip lines, of which **five belong to earlier tests**.
Two consequences the ledger does not state: `#expect(!skipped.isEmpty, "the store logged nothing for a record it skipped")` is not specific to this test and can be satisfied by a sibling's line, and the `for line in skipped` loop asserts about output this test did not produce, so a future unrelated persistence log line failing the `<private>` or value check would fail *this* test and point at the wrong code.
Only `#expect(skipped.contains { $0.contains("Subscription.cycleStartDay") })` discriminates, and it is the assertion that caught all three of my falsifications.

**not flaky, as far as I could push it.** 6 full-suite runs, 5 isolated runs of `theEmittedLineIsRedacted`, and 6 concurrently launched runs - 17 executions, zero failures. `OSLogStore(scope: .currentProcessIdentifier)` correctly isolates concurrent test processes from one another.

**why the builder missed it.** The observed symptom (`StoredSubscription.status is missing`) genuinely is another test's line, so "another test's line got in" was right; "because suites run concurrently" was the first available explanation and was never checked against `TestSupport.swift`, which is the file that exists to say otherwise. The remedy adopted happens to tolerate the real mechanism, so nothing forced the diagnosis to be re-derived.

### 5. P3 - round 1's reason for declining the `OSLogStore` guard is cited by half, and the half dropped is the live risk

**evidence.** `PROD-READINESS-2.md:265`: *"`reviews/REVIEW-5.md` demonstrated this and round 1 declined it on cost; the cost is real and is recorded below."*

`PROD-READINESS.md:184` says: *"it costs 11-27 s against a ~2 s suite **and depends on the log daemon being readable**."*
`reviews/REVIEW-5.md:163` says: *"a log-store read is exactly the kind of environment-dependent assertion `BASELINE.md:21-26` warns about. Those are cost **and flakiness** arguments."*

Round 1 gave two reasons; the ledger repeats one. The "Costs and limits, stated" paragraph (`:276`) covers duration and the private-data limit and never mentions environment dependence.
This is not academic: `.github/workflows/ci.yml`'s `persistence-tests` job now runs a test that requires `OSLogStore` to be readable on a GitHub-hosted `macos-26` runner, an environment nobody in this run can exercise (network is prohibited), and `docs/next-wave.md` records that CI's first run found a host-environment dependency **twice** for exactly this reason.

**why the builder missed it.** `reviews/REVIEW-5.md`'s argument is that the *stated* reason ("cannot be done without asserting about the host") was false and that cost would have been an honest reason. Reading it for the correction, the second honest reason it also offered fell out.

### 6. P3 - ITEM 4's falsification table still names a symbol this stage deleted

**evidence.** `PROD-READINESS-2.md:245`:

> `| hasNoLiveRecords forced to false | both the all-tombstoned and the empty-database tests fail |`

`hasNoLiveRecords` does not exist at HEAD; `d00c086` renamed it. The other two rows in the same table were reworded for the new predicate and this one was not.
Re-derived against `hasNoLiveSubscriptions` the row's substance holds and is understated: `ExportServiceTests.swift:141`, `:182`, `:196` **plus** `ExportImportTests.swift:16`, `:34`. Row 2 is likewise now incomplete - pinning the predicate `true` also fails `ExportImportTests.swift:47`, because the stage added domain-side tests after that table was written.

**why the builder missed it.** This is the fourth recurrence of "a citation measured before a move and never re-derived" in this run (`reviews-2/REVIEW-3.md` finding 4, and `PROD-READINESS-2.md:219` records the third). The table was treated as settled evidence rather than as text that names symbols.

### 7. P3 - the offending value is now unrecoverable from any surface, and one of the two sites pays that cost for no privacy gain

**evidence.** `mapSkippingFailures` discards the caught error (`OttoStore.swift:119-126`), and no other surface carries it: `unreadableSubscriptionCount()` returns a count (`OttoStore+Subscriptions.swift:36-43`) and `subscriptionReadRepairs()` never sees a throwing record (`:53`). `description` keeping the value is real but has no reader.
So after this change the invalid value exists nowhere - not in the log, not with a private-data profile, not in a sysdiagnose. The ledger states only the upside (`:261`, "*more* useful than what it replaced").

At `CancellationEpisodeMapping.swift:184` the trade is pure loss: the caught error is a SwiftData fetch failure that cannot be a `MappingError`, so `mappingLogSummary` reduces a full error description to a bare type name and removes no user content.

**severity P3 and stated as a trade, not a defect.** On the default read the fix is strictly better - `<private>` told an investigator nothing. Discarding a value that distinguishes a Feb-30 packing artifact from a zero from garbage is a real diagnosability cost, and it is the kind of cost this ledger normally states.

**why the builder missed it.** The finding is framed as "the value must not reach the log", and the fix answers it exactly. Nothing in the framing prompts the question "and who needed that value".

### 8. P3 - a real card detail was copied into a new source fixture, in the stage whose subject is card details

**evidence.** `Packages/OttoUI/Tests/OttoServicesTests/ExportServiceTests.swift:170-176` adds `label: "Bank"`, `last4: "XXXX"`, `issuer: "Bank"`.
`reviews-2/BASELINE-2.md:123` records the real device's payment method as *"Credit card ••XXXX Bank"*.

**not a new exposure** - `git grep -l <last4> 7a3cf54` shows `docs/next-wave.md` and `reviews/BASELINE.md` already carry it, and no `.swift` file did before this stage. The surrounding fixture already uses the synthetic `"4821"`, which is what a new one should have used. One token to change.

---

## Checked and found clean

- **No SwiftData schema change.** No file under `Packages/OttoPersistence/Sources/OttoPersistence/Schema/` appears in `git diff --name-only 989ece0..5d8ed6a`. The V3 freeze holds. `MappingLogPrivacyTests` mutates `record.cycleStartDay` on an existing `StoredSubscription` attribute; it declares nothing.
- **No prohibited action by the builder.** `.swiftlint.yml`, `.github/workflows/`, `project.yml`, every `Package.swift`, `PROD-READINESS.md`, `reviews/`, `DECISIONS.md` and `docs/` are all absent from the range's file list. No new dependency, no new config key. `refs/remotes/origin/main` is unchanged at `406a5a6`, there is no `.git/FETCH_HEAD`, `ORIG_HEAD` dates from Aug 8, `git tag` is empty, and the reflog for the range contains only `commit:` entries - no fetch, push, rebase, reset or tag deletion.
- **The file split is required, not reorganisation.** `.swiftlint.yml` sets no `file_length`, so SwiftLint's default 400-line warning applies and `--strict` promotes it. `PreviewSupport.swift` was 398 lines; adding `seedNeedsReview` and its two stored properties takes the combined content to 420. The scope constraint explicitly permits splitting a file that outgrows a limit, and `.swiftlint.yml` is untouched. `PreviewRepository` is `#if DEBUG` and its two seeded properties default to the previous constants, so preview behaviour is unchanged.
- **No feature smuggled in.** The only new public API is `OttoDataSnapshot.hasNoLiveSubscriptions`, which replaces `hasNoLiveRecords` one-for-one at its single call site. `MappingError.logSummary` and `mappingLogSummary(_:)` are internal. No user-visible copy, view, or setting changed.
- **No test skipped, disabled or weakened.** No `.disabled(`, `.enabled(if:`, `withKnownIssue`, `throws:` relaxation, or deleted test in the range. The two assertion edits both **strengthen**: `TodaySectionPlanTests` restores exact equality that REVIEW-4 finding 4 said was dropped further than the locale repair required, and `ExportServiceTests` replaces a tombstoned payment-method fixture with a live one, which is the harder case. The simulator's known-issue count is 7 before and after.
- **No fix relocated a bug.** `hasNoLiveSubscriptions` strictly widens `isEmpty`, and `.reconstruct` can only pull a watermark earlier under the v2.5 cap, so no input that reconstructed before stops doing so and no watermark advances. `description` keeping the value is deliberate and the two call sites are the only readers of a caught mapping error in the package. The §5.3 dirty-flag second-order effect is disclosed at `:235`.
- **No remaining path can put an amount, a vendor name or URL, or a card detail into a log line.** I enumerated every logging call in `Packages/*/Sources` and `Otto/`: 16 sites in `OttoServices` and 2 in `OttoPersistence`, and there is no `print`, `debugPrint`, `NSLog` or bare `os_log` anywhere in a source target. Every `.public` slot is a trigger name, a bare count, a `CalendarDay`, a `<uuid>|<day>|<kind>` identifier, a fixed action constant, or an error **type** name. `mappingLogger` has exactly two call sites and both take `mappingLogSummary`. The one survivor of the `String(describing: error)` idiom is `NotificationCoordinator.swift:145`, which describes a `BGTaskScheduler.submit` failure and cannot carry user content; it is inconsistent with the convention but is pre-existing and outside R0-4.
- **Citations spot-checked and correct.** `SubscriptionMapping.swift:156-160` really does throw `value: "\(lengthDays)/\(bufferDays)/\(convertsTo)"` with `convertsTo` bound from `convertsToAmountCents`; `StorageShapes.swift:54-58` really is `URL.storedOptional` throwing the raw string, reached at `SubscriptionMapping.swift:43` and `:55` for `vendorURL` and `cancellationURL`; `OttoLog.swift:20-21` carries the quoted doctrine verbatim; `storedNoteAnywhere` is the real function name at `CancellationEpisodeMapping.swift:175`; `PROD-READINESS.md:113` does rate R0-4 P2 partly on default `.private` interpolation; `reviews/REVIEW-5.md:154` does demonstrate the `OSLogStore` technique; F2's line at `NotificationActionHandler.swift:78` does use `type(of: error)`, so "the convention F2's line already uses" holds. The exceptions are findings 5 and 6.
- **Verification exercises the changed path.** `theEmittedLineIsRedacted` drives a real `OttoStore` over real SwiftData containers, corrupts a real column, reads through the real `mapSkippingFailures`, and reads the line back out of the process's own log. Deleting the emission fails it; reverting the call site fails it; re-interpolating the value fails it. The only unexercised half is finding 3.
- **Nothing marked RESOLVED without an artifact**, in the sense that an artifact exists and I ran it. R0-4's `0b76d65` is green at HEAD. The problem in finding 2 is that R3-1 names the *wrong* artifact, not that it names none.
- **Severity, checked in both directions.** R0-4 stays P2, which is round 1's rating and right - the exposure needs a corrupt or partially synced record plus a sysdiagnose. Nothing in the ledger inflates it: the `<private>` paragraph is careful to say the finding is about what was *written*, not what was displayed. Nothing deflates it either; the ledger does not lean on `.private` as a mitigation. N2-3's withdrawal is correct - the case it deferred is now covered, and I confirmed the withdrawn text's claim about price changes and cancellation episodes was wrong, as REVIEW-4 measured.

## Prohibited actions by me: none

All falsification was done in four scratch clones under the session scratchpad (`prev` at `989ece0`, `mid` at `d00c086`, `head` and `fals` at `5d8ed6a`), never in the repository. Every clone was restored with `git checkout -- .` and confirmed empty by `git status --porcelain` after each experiment. No network call of any kind: `scripts/verify.sh` and my clones all read the local repository over a filesystem path, and I inspected refs with `git show-ref` and `git log` only. No physical device; the simulator (`<simulator-udid>`) was used as permitted. Nothing in `<backup-dir>` was read, moved or modified; no file was deleted that I did not create; no `rm -rf` on any path outside the scratchpad clones I created myself. This file is the only file I wrote.

The repository is at `5d8ed6a` with `git status --porcelain` empty.
