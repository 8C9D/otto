# REVIEW-1 - stage 1, range 8806853..87d6508

verdict: PASS-WITH-FINDINGS

The stage is small and honest.
Two commits, 387 added lines, one of them a test; zero production lines changed; zero deletions anywhere under `Packages/`.
Every falsification the ledger reports, I reproduced verbatim - same failure text, same line numbers.
The baseline is intact on all four measurements.

The findings below do not invalidate the stage.
One of them (finding 1) does weaken the argument the run uses to gate stage 2, and should be closed before item 1 adds `OttoSchemaV4`.

## What I ran

**Range and scope.**

```
$ git log --oneline 8806853..87d6508
87d6508 Relate the migration plan's stages to its schemas, by chain rather than by count
8f86c1f Re-derive the round-3 baseline and open the ledger

$ git diff --name-status 8806853..87d6508
A	PROD-READINESS-3.md
M	Packages/OttoPersistence/Tests/OttoPersistenceTests/CloudKitCompatibilityTests.swift
A	reviews-3/BASELINE-3.md

$ git diff 8806853..87d6508 -- 'Packages/' | grep -c '^-[^-]'
0
```

No schema file, no `.github/workflows/`, no `.swiftlint.yml`, no narrative document is in the diff.
The only code change is +74 lines of test, purely additive.

**Baseline re-derivation at HEAD (`87d6508`), all four measurements.**

```
$ ./scripts/verify.sh            # exit 0
== VERIFIED: 87d65082af0b07706cc53c952a681f202b16e50c builds, tests, and lints from a clean clone
   OttoDomain: 251
   OttoPersistence: 119
   OttoUI: 196
   total: 566 tests
```

`swiftlint --strict` runs inside that and passed; I also ran it directly on the working tree (`swiftlint --strict --quiet`, exit 0, SwiftLint 0.65.0).

```
$ cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"   # exit 0
✔ Test run with 108 tests in 20 suites passed after 2.894 seconds.
✔ Test run with 70 tests in 12 suites passed after 0.073 seconds.
✘ Test run with 31 tests in 6 suites passed after 3.206 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Non-Gregorian harness, the command from `CalendarEraTests.swift:15-20`, all three locales:

```
th_TH@calendar=buddhist        ✘ 196 tests ... failed with 1 issue   (DisplayFormattingTests.swift:49)
ja_JP@calendar=japanese        ✘ 196 tests ... failed with 1 issue   (DisplayFormattingTests.swift:49)
ar_SA@calendar=islamic-umalqura ✘ 196 tests ... failed with 5 issues (DisplayFormattingTests.swift:49,59,68,69; NotificationReconciliationTests.swift:170)
```

565 → 566 and 118 → 119 is the one new test and nothing else.
Simulator 108 / 70 / 31 with 7 known issues, and non-Gregorian 1 / 1 / 5 at the same five file:line citations, are byte-for-byte what `reviews-3/BASELINE-3.md:12-15` records.
**No regression.**

**Every commit in the range builds.**

```
$ git worktree add --detach <scratch> 8f86c1f
$ swift build --build-tests --package-path Packages/OttoDomain      Build complete! (17.76s)
$ swift build --build-tests --package-path Packages/OttoPersistence Build complete! (32.77s)
$ swift build --build-tests --package-path Packages/OttoUI          Build complete! (45.18s)
```

`87d6508` is covered by `verify.sh`, which clones the committed HEAD and builds the app target as well.
Worktree removed; `git worktree list` shows only the repository.

**Mutation testing of the one new test** (check 10).
Each mutation was applied to the working tree, measured, then reverted with `git checkout --`; probe files were ones I created and I deleted only those.
`git status --porcelain` is empty now and was verified empty after every revert.

| mutation | result |
|---|---|
| `OttoSchemaV4` appended to `schemas`, `mainSchema` repointed, no stage - the R0-9 reproduction verbatim | `✘ ... CloudKitCompatibilityTests.swift:60:13: Expectation failed: (stages.count → 2) == (versions.count - 1 → 3)`; **119 tests, exactly 1 issue** |
| plus a wrong stage `.lightweight(V2 → V4)`, so the count is right again | `✘ ... :74:17: Expectation failed: (hop.fromVersion → 2.0.0) == (versions[index] → 3.0.0)` |
| extraction labels renamed `fromVersion`/`toVersion` → `fromV`/`toV` | `✘ ... :66:31: Expectation failed: (Self → CloudKitCompatibilityTests).versions(of: stage → .custom(fromVersion: OttoPersistence.OttoSchemaV1, ...)) → nil` |
| `versions(of:)` body replaced by a compiler-checked `switch` | test passes (finding 2) |
| `OttoSchemaV4` with `Schema.Version(3, 0, 0)` plus a correct-looking stage `V3 → V4` | **both guards pass** (finding 1) |

Row 1 is the strongest single result in the review.
The mutated suite reports **119 tests with exactly one issue**, and that issue is the new test - which independently confirms the ledger's reproduction claim (`PROD-READINESS-3.md:87-94`) that the other 118 stay green under the R0-9 defect, and confirms that the new test is the only thing standing between the repository and that defect.

Row 2 also settles a ledger claim the shipped suite cannot settle: the plan contains no `.lightweight` stage today, so `PROD-READINESS-3.md:104`'s "works identically for `.lightweight` and `.custom`" is untested in-repo.
I exercised it with a real `.lightweight` stage; the `#require` at `:66` passed and the failure landed at `:74`, so the extraction did read a lightweight payload.
The claim is true.

**Citations opened and checked** (check 2).

- `PROD-READINESS-3.md:87` cites `reviews/REVIEW-0.md:276`. Exact: line 276 is the "Append `OttoSchemaV4` to `schemas` and point `mainSchema` at it without adding a stage" sentence. ✅
- `PROD-READINESS-3.md:102` cites `reviews/REVIEW-0.md` for the `stages.count == schemas.count - 1` proposal. **Wrong file** - see finding 3.
- `PROD-READINESS-3.md:98` "the file that already owns this contract" - `CloudKitCompatibilityTests.swift:6-20` is indeed the staleness-hazard header. ✅
- `PROD-READINESS-3.md:107` "this file's own header records that happening once ... stayed green through Wave 6A" - `CloudKitCompatibilityTests.swift:6-8` says exactly that. ✅
- `PROD-READINESS-3.md:121` "118 to 119" - measured, exact. ✅
- `PROD-READINESS-3.md:120` "~0.001 s" - measured 0.001-0.004 s. ✅
- `PROD-READINESS-3.md:27` / `BASELINE-3.md:42-53` "all four `OSLogStore` tests pass at HEAD". I counted the store-reading tests: `SchedulingLogTests.swift:44` (via the helper at `:93`), `NotificationActionLogTests.swift:35` and `:73` (via `:106`), `MappingLogPrivacyTests.swift:61` (via `:107`) - **exactly four**, and the suite totals quoted (5 in 2 suites, 3 in 2 suites) match those files' `@Test` counts. All pass, inside my `verify.sh` and OttoPersistence runs. ✅
- `BASELINE-3.md:26-35` provenance. Re-derived without a network call: `git show-ref` gives `refs/remotes/origin/main 406a5a6`, `git merge-base main HEAD` gives `406a5a6`, and `git log --oneline main..8806853 | wc -l` gives **48** - the number was measured at `8806853` and is correct there (it is 50 at current HEAD). ✅

## Findings

### 1. The chain guard goes green on a schema version whose identifier was never bumped - the exact copy-paste mistake stage 2 is about to be able to make

- **severity: P2**
- **evidence:**

  The test is named "every schema version after the first is reached by a stage, **in order**" (`Packages/OttoPersistence/Tests/OttoPersistenceTests/CloudKitCompatibilityTests.swift:52`), but nothing in its body asserts that the versions are ordered, or even distinct.
  It compares `hop.fromVersion` to `versions[index]` and `hop.toVersion` to `versions[index + 1]` (`:74-81`) and nothing else.

  I added a throwaway fourth schema carrying V3's models with its identifier left at V3's - the single most likely error when a new version is created by copying the old one:

  ```swift
  enum OttoSchemaV4: VersionedSchema {
      static let versionIdentifier = Schema.Version(3, 0, 0)   // not bumped
      static var models: [any PersistentModel.Type] { OttoSchemaV3.models }
  }
  ```

  with `schemas` extended to four entries and `stages` extended by `.lightweight(fromVersion: OttoSchemaV3.self, toVersion: OttoSchemaV4.self)`:

  ```
  $ swift test --package-path Packages/OttoPersistence --filter "stagesChainTheSchemas|guardTargetsTheLiveSchema"
  ✔ Test "the schema under test IS the schema the app opens, at the migration plan's terminal version" passed after 0.008 seconds.
  ✔ Test "every schema version after the first is reached by a stage, in order" passed after 0.001 seconds.
  ✔ Test run with 2 tests in 2 suites passed after 0.009 seconds.
  ```

  Both guards green on a plan whose chain is `1.0.0 → 2.0.0 → 3.0.0 → 3.0.0`.
  `guardTargetsTheLiveSchema` cannot see it either: `live.version == terminal.versionIdentifier` holds trivially, and the entity-name comparison is identical whenever the new version keeps the same entities - which is what a value-repair migration such as item 1's does.

  This matters more than a generic guard gap because of `PROD-READINESS-3.md:50-52`: the run reorders items 1 and 2 specifically so that this test exists *before* the schema freeze is lifted.
  The gate is real for a missing stage and for a mis-wired stage; it is absent for an unbumped identifier, and the resulting plan is one SwiftData cannot stage at all.
  `PROD-READINESS-3.md:123-125` ("What this does NOT do") discloses only that stage *bodies* are unchecked; it does not name this.

  The fix is one assertion inside the existing loop, so closing it is not scope creep.

- **why the builder missed it:** the falsification set is three-for-three on the `stages` side of the relation - a stage removed, a stage mis-wired, the extraction broken - and zero on the `schemas` side. Every mutation varied the thing the finding was written about. Nothing varied a `versionIdentifier`, which is the only input to `versions` and the only value the assertions compare.

### 2. The reflection is not required: `MigrationStage`'s cases are public and pattern-matchable, and the ledger's justification for reflection describes the API incompletely

- **severity: P3**
- **evidence:**

  `PROD-READINESS-3.md:104` and `CloudKitCompatibilityTests.swift:87` both say `MigrationStage` "publishes no accessor for them, so this reads the enum's own payload by reflection".
  Literally true - there is no `fromVersion` property - but it reads as "there is no supported way to obtain the endpoints", and that is false.
  Against this host's SDK:

  ```
  $ cat probe.swift
  import SwiftData
  func endpoints(_ stage: MigrationStage) -> (any VersionedSchema.Type, any VersionedSchema.Type)? {
      switch stage {
      case .lightweight(let from, let to): return (from, to)
      case .custom(let from, let to, _, _): return (from, to)
      @unknown default: return nil
      }
  }
  $ swiftc -typecheck -sdk $(xcrun --show-sdk-path --sdk macosx) -target arm64-apple-macos15.0 probe.swift
  EXIT=0
  ```

  Negative control, to prove the probe resolves the real type rather than passing vacuously - renaming the case to `.lightweightXX` gives
  `error: expression pattern of type 'SwiftDataError' cannot match values of type 'MigrationStage'`.

  Substituting that switch for the 17-line `versions(of:)` body keeps the test green (mutation table, row 4).

  The consequence is not correctness - the reflection works and I verified it fails closed (mutation row 3) - it is the direction of failure on an SDK change.
  With the switch, a renamed label or reordered payload is a **compile error at the moment of the Xcode upgrade**.
  With `Mirror`, it is a **runtime nil** that turns the suite red later, and it also makes the `Optional` return, the `#require`, and the three-line "THIS GUARD IS NOT GUARDING" message necessary in the first place - machinery the compiler-checked form does not need.
  A new SwiftData case fails closed identically under both forms (`@unknown default` returns nil).

  This is also the range's only environment-dependent construct: it couples an OttoPersistence test to the Swift runtime's reflection of an OS-framework enum's payload.

- **why the builder missed it:** the ledger's reasoning starts from "there is no accessor", which is a search for a *property*. Public enum cases are the accessor here, and asking "is there a property" does not surface them. The `Mirror` design then became self-justifying: once the extraction can fail at runtime, a fail-closed story is required, and the fail-closed story reads as evidence the design was necessary.

### 3. A citation that points at the wrong file

- **severity: P3**
- **evidence:** `PROD-READINESS-3.md:102` reads "`reviews/REVIEW-0.md` proposes `stages.count == schemas.count - 1`."

  ```
  $ grep -n "stages.count" reviews/REVIEW-0.md PROD-READINESS.md PROD-READINESS-2.md reviews/*.md
  PROD-READINESS.md:76:| R0-9 | ... | Assert `stages.count == schemas.count - 1`. | ...
  ```

  The string does not occur in `reviews/REVIEW-0.md` at all.
  Its R0-9 section (`reviews/REVIEW-0.md:253-284`) diagnoses the gap and proposes no assertion; the proposal lives in the recommendation column of `PROD-READINESS.md:76`, whose source column names REVIEW 0.
  The substance is right and the attribution of origin is right; the file citation is wrong, and the argument at `:101-103` is built on it.
- **why the builder missed it:** the round-1 ledger row and the round-1 review say nearly the same thing about R0-9, and the row credits REVIEW 0 in its own source column, so quoting the row while citing the review is a single-step conflation that re-reading the review would not obviously flag.

### 4. `aa92ca7` has never been inside any review range, in either round - inherited, and the range table does not say so

- **severity: P3**
- **evidence:** round 2's last review covered `5d8ed6a..3ce3e01` (`reviews-2/REVIEW-6.md:3`), and `reviews-2/` contains REVIEW-1 through REVIEW-6 and nothing later.
  `git log --oneline -3 8806853` shows `8806853` (docs) on `aa92ca7` ("Give the failure list its own log entry, and make an empty log diagnosable" - a code commit) on `70f3f19` (the review document).
  Both land after `3ce3e01`.
  Round 3's stage-1 range starts at `8806853`, so `aa92ca7`'s diff is outside every review range that has ever been issued.

  This is inherited, not created: the round-3 prompt fixes `8806853` as the starting point (`PROD-READINESS-3.md:80`, ASSUMPTION 4), and `BASELINE-3.md` does verify the *state* at `8806853` by re-running all three commands, so nothing unbuilt or untested is being carried.
  `PROD-READINESS-3.md:64` is carefully worded ("no commit **in this run** is a range boundary that nobody read") and is true as written.
  Recorded because the run's own standard is to name what it did not close, and the range table's rule at `:56` ("each stage's range starts at the previous stage's reviewed head") has one row, and that row does not start at a reviewed head.
- **why the builder missed it:** the rule was written for stage-to-stage chaining inside a run; the run's first range has no previous stage, so the rule silently does not apply exactly where the gap is.

## Explicit checks

1. **Fabricated or unreproducible findings** - **none.** Every claim in `## ITEM 2` that can be executed, I executed. The three-row falsification table at `PROD-READINESS-3.md:112-116` reproduces with byte-identical failure text and matching line numbers. The reproduction claim at `:87-94` reproduces, and my run strengthens it: 119 tests with exactly one issue proves the other 118 are indifferent to the defect.
2. **Citations that don't say what they're claimed to say** - **one**, finding 3. All others opened and correct, listed above.
3. **Severity inflation or deflation** - **none found.** The ledger assigns no severity to item 2; round 1 carried R0-9 at P2 (`PROD-READINESS.md:76`), and a guard gap with no user impact today is a fair P2. Nothing is overstated: `## What this does NOT do` (`:123-125`) is a genuine limitation section, not a hedge, and it is accurate as far as it goes (finding 1 is what it omits).
4. **Features smuggled past the no-features rule** - **none.** Zero production lines changed in the range; the only executable change is a test and a private test helper.
5. **SwiftData schema change outside item 1's authorization** - **none.** `git diff --name-only 8806853..87d6508` matches no path under `Sources/OttoPersistence/Schema/`. `OttoMigrationPlan.swift` still reads `[OttoSchemaV1.self, OttoSchemaV2.self, OttoSchemaV3.self]` / `[migrateV1toV2, migrateV2toV3]` at `:13-19`. The freeze holds.
6. **Prohibited actions** - **none found.** No tags exist. `refs/remotes/origin/main` is `406a5a6`, equal to `git merge-base main HEAD`. `.git/FETCH_HEAD` does not exist, so no fetch or pull has ever run in this clone. `.git/ORIG_HEAD` is dated Aug 8, predating the run, so no rebase or reset in the range. The reflog shows exactly one checkout and two commits since branching, with no amend, rebase or reset entries. `<backup-dir>` untouched. I made no network call and ran no `ls-remote`/`fetch`/`pull`.
7. **Fixes that relocated a bug** - **N/A.** There is no production change to relocate anything into.
8. **Error handling that hides errors** - **none.** `versions(of:)` (`CloudKitCompatibilityTests.swift:96-112`) does `continue` on unrecognised children and `return nil` on a failed extraction, but the caller converts nil into a hard `#require` failure with a message naming the cause (`:66-73`). I broke the extraction and watched it fail loudly (mutation row 3) rather than skip the stage. Verified, not assumed.
9. **Verification that doesn't exercise the changed path** - **no.** The builder's falsification table mutates precisely the two literals the test relates, and I reproduced each. The one claim the committed suite cannot exercise - the `.lightweight` half of the extraction - I exercised separately and it holds (mutation row 2).
10. **Tests that pass for the wrong reason** - **no.** One test was added, none changed, none deleted, no assertion weakened (zero deletions under `Packages/`). I removed the thing it guards, four different ways, and it failed all four times with the message the failure deserves. It is load-bearing on the count, on the chain, and on the extraction independently. Its one blind spot is finding 1.
11. **Flaky or environment-dependent tests** - **one dependency, not a flake.** The new test reads no clock, no locale, no calendar, no log daemon, no host state, and does no concurrency or ordering-sensitive work; it ran in 0.001-0.004 s across every invocation. It does depend on the Swift runtime's reflection of `MigrationStage`'s payload, which is an unspecified SDK implementation detail (finding 2). That dependency fails closed and loudly, so it is a maintenance cost on Xcode upgrades rather than nondeterminism.
12. **Anything marked resolved without an artifact** - **no.** Item 2 is the only row moved to RESOLVED, and its artifact is a committed test whose falsifications I reproduced.
13. **Every commit in the range builds** - **yes, both.** `8f86c1f` built all three packages with `--build-tests` in a detached worktree; `87d6508` is covered by `verify.sh`, which clones the committed HEAD and additionally builds the app target under `xcodebuild`. No non-compiling commit in the range.
14. **Baseline not regressed** - **verified, all four, by running them.** `verify.sh` exit 0 at 251 / 119 / 196 = 566 (the +1 is the new test and nothing else); `swiftlint --strict` clean both inside `verify.sh` and directly; simulator 108 / 70 / 31 with 7 known issues and `** TEST SUCCEEDED **`; non-Gregorian 1 / 1 / 5 at the same five citations `BASELINE-3.md:143-171` records. Nothing was reasoned about here - all four were measured.

## What I could not check, and why

- **Release configuration.** Nothing in the range is configuration-sensitive, but I built and ran Debug only, matching `PROD-READINESS-3.md:78`.
- **Physical device, real notification delivery, CloudKit.** Prohibited or absent; unchanged from the run's CANNOT ASSESS list, and nothing in this range touches those paths.
- **CI runners.** Whether `OSLogStore(scope: .currentProcessIdentifier)` is readable on GitHub-hosted runners is untestable from here without a network call. I confirmed all four such tests pass on this host, which is the same evidence the ledger claims and no more.
- **Other Xcode toolchains.** Finding 2's failure mode - reflection breaking on an SDK change - is by construction unobservable on the single toolchain available (Xcode 26.3, SDK MacOSX26.2). I verified the pattern-matching alternative compiles *here*; I cannot verify how either form behaves on a future SDK.
- **Whether SwiftData actually rejects a plan with a duplicated `versionIdentifier`** (finding 1). I proved the guards accept it; I did not open a store against such a plan to observe the runtime failure, because doing so would mean running a migration against a deliberately malformed plan and I judged the guard-level evidence sufficient to make the point.

Working tree was restored after every mutation and is clean: `git status --porcelain` is empty, `git worktree list` shows only the repository, and no commit was created by this review.
