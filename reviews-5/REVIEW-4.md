# REVIEW-4 - round 5, stage 3, items 3, 6 and 7 (N2-4 reopened + N4-10 + N4-11), range `cdb509e..7b6df8c`

Reviewed head `7b6df8cdff802775f386a7defa83f63edc97bda3`, branch `prod-readiness-5/2026-08-15`.
The range contains six commits: `773672c` (the R3 review artifact, `reviews-5/REVIEW-3.md` only), `e93dabb` (the finding-routing commit - `PROD-READINESS-5.md` plus the `docs/next-wave.md` snooze-carve-out paragraph REVIEW-3 finding 1 asked for; no code, verified by `--name-only`), `bba63cb` (item 3), `2f74aa8` (item 6), `ebd85c9` (item 7), `7b6df8c` (ledger only).
At review time `git status --porcelain` showed only an untracked `.claude/` directory, present before this session and not mine; `HEAD == 7b6df8c` before this file was added.
All mutation and probe work was done in one detached worktree at `7b6df8c` under my own scratchpad; every mutated file was restored from a saved pristine copy and byte-compared with `cmp`, the worktree was `git status --porcelain` clean before removal, and `git worktree list` now shows only the main tree.
The main working tree was never modified except to write this file.

verdict: PASS-WITH-FINDINGS

## Summary

**All three closures are real, and I could not break any of them or catch a measured claim in a false number.**
Item 3's ceiling test genuinely drives 64 refused rungs through the real `reconcile` loop and asserts every one of the 64 by byte-for-byte equality on its own complete entry: reverting to the round-2 aggregate fails it with exactly 64 issues, capping the per-rung loop at `prefix(15)` fails it with exactly 49 - the ledger's M1 and M2 shapes - and a scheduler that silently drops rungs cannot shrink the expected set in lockstep, because `#expect(attempted.count == 64)` pins the set's size to the device-ceiling constant and my `specs.prefix(32)` mutant died on that line plus a pre-existing 200-subscription budget pin.
Item 6's guard fails on wholesale deletion of the diff statement (1 issue, identical on three full host runs) and on single-field regressions of the identifier lists - my `removed=[...]`-field deletion was caught by the `removed=[-]` assertion - and its disclosed non-scope (numeric `pending=`/`desired=` values) is honest, with one gap recorded as finding 2.
Item 7's per-test canary does what the record says in full-suite runs with no `--filter`: deleting either host's emission line no longer compiles (`cannot find 'canary' in scope`, demonstrated on both hosts), and the executable mutant - mint-without-emit - fails exactly its own test at `requireDelivered` on three of three full-suite runs per host, where the same deletions were measured green at the stage start.
The five dimensions reproduce exactly: verify.sh exit 0 at 265/127/227 = 619, lint clean over 230 files, the simulator suite at 132/72/63 with 9 known issues and `** TEST SUCCEEDED **` on three consecutive full runs, the harness at 1/1/5 with the same five citations, and every pristine host run green at 227.
The -1 test delta reconciles to exactly the deleted `noFailures`, whose only assertion - the empty aggregate renders as `"-"` - was production-unreachable at the range start anyway, because the aggregate emission sat inside `if !failures.isEmpty`.

**Both findings are record-edge, not code.**
Item 7's ledger counts "ten emission sites and ten `requireDelivered` sites"; the measured numbers are eleven and eleven at the head, and the ten is the reader count wearing the wrong label - the same off-by-one population class `reviews-4/REVIEW-AA92CA7.md` findings 3 and 6 recorded.
And the one field item 3's drop rationale leans on - "the diff line's `failedCount=` keeps the total" - is executable-guarded only at zero: hardcoding `failedCount=0` into the production statement survives the full 227-test suite.

## What I ran

All measurements at `7b6df8c` unless stated.
Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five dimensions at the stage-3 head

| dimension | ledger claims (at `ebd85c9`; `7b6df8c` adds only the ledger) | measured here | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0, 265/127/227 = 619 | **exit 0; OttoDomain 265 / OttoPersistence 127 / OttoUI 227 = 619**, from a clean clone of the committed head | exact |
| `swiftlint --strict` | clean, 230 files | **0 violations, 0 serious in 230 files** | exact |
| simulator suite, full | 132/72/63, 9 known issues, `TEST SUCCEEDED` | **132 / 72 / 63, `with 9 known issues`, `** TEST SUCCEEDED **`** on all three full runs | exact; the 9 = the 7 `EmptyStateTests` issues + the 2 in "The usage repair renders (N4-16)", by name in the logs |
| non-Gregorian harness | 1 / 1 / 5, same citations | **1 / 1 / 5** (227-test bundle): `DisplayFormattingTests.swift:49` under Buddhist and Japanese; `:49`, `:59`, `:68`, `:69` and `NotificationReconciliationTests.swift:170` under `ar_SA` | exact |
| flake, twelve full host runs | 12 of 12 (227 tests per run) | **5 of 5 pristine full OttoUI runs green** (three dedicated, verify.sh's, and the post-battery run on restored files), 227 tests each; I did not re-run twelve | consistent; the 12/12 itself is unreplicated |

### The -1 test delta, reconciled to the test

`@Test` counts per changed test file across the range: every file is unchanged except `SchedulingLogTests.swift`, 5 -> 4.
The diff shows one deletion (`noFailures`) and two same-place renames (`failuresCarryReasonsPerRung` -> `failedRungCarriesItsReason`, `theEmittedReconcileLineCarriesReasons` -> `everyFailedRungIsNamedAtTheCeiling`), so the -1 is exactly the recorded deletion, and the simulator's first bucket moving 133 -> 132 is the same test.

### Per-commit build sweep

`bba63cb`, `2f74aa8` and `ebd85c9` each build `--build-tests` for OttoUI; `ebd85c9` and the head also build OttoPersistence; the head is additionally covered by verify.sh from a clean clone.
`773672c` and `e93dabb` carry no buildable change (`--name-only`: one review artifact; ledger plus user doc).

### The reader count, re-enumerated by the baseline's method

Counting call sites of the four store-opening helpers, as `reviews-5/BASELINE-5.md` does: `actionLogLines` 4, `schedulingLogLines` 2, `boundaryLines` 1, `OttoLogProbe.persistenceLines` 3 - **ten**, unchanged.
The ceiling test inherits its predecessor's `schedulingLogLines` call site, as the ledger says, and item 6's guard reads inside `theEmittedSkipLineNamesTheDays`' already-open query; no query was added anywhere in the range.

### Falsifications - the stage's five reproduced, plus four of my own

Each mutation was applied by a script that asserted the target text's occurrence count was 1, in the worktree, and restored from a pristine copy verified with `cmp`; every suite run is a FULL host run with no `--filter` and no suppressed subsystem.

The stage's battery, reproduced:

| ledger mutant | exact change I applied | ledger says | measured |
|---|---|---|---|
| item 3 M1 | per-rung loop replaced by the round-2 aggregate (sorted join, one `reconcile failed=[...]` entry) | `everyFailedRungIsNamedAtTheCeiling`, 64/64/64 | **the same one test, 64 issues** (one run) |
| item 3 M2 | `for failure in failures` -> `failures.prefix(15)` | same test, 49/49/49 | **the same one test, 49 / 49 / 49** on three full runs |
| item 6 M3 | the whole diff `notice` statement deleted | `theEmittedSkipLineNamesTheDays`, 1/1/1 | **the same one test, 1 / 1 / 1** on three full runs, failing at the diff-line `#require` -> nil |
| item 7 M4 | ceiling test's `emitCanary(to:)` -> bare minted literal | `everyFailedRungIsNamedAtTheCeiling` at `requireDelivered`, 1/1/1 | **exact**: fails at `SchedulingLogTests.swift:129` (`lines.contains { $0.contains(canary) }`), 1 / 1 / 1, three full OttoUI runs |
| item 7 M5 | `MappingLogPrivacyTests`' `emitCanary()` -> bare minted literal | `theEmittedLineIsRedacted` at `requireDelivered`, 1/1/1 | **exact**: fails at `MappingLogPrivacyTests.swift:98`, 1 / 1 / 1, three full OttoPersistence runs |
| item 7, compile shape | the `let canary = ...emitCanary...` line deleted outright, once per host | fails to compile: `cannot find 'canary' in scope` | **exact on both hosts** (`SchedulingLogTests.swift:128`, `MappingLogPrivacyTests.swift:97`) |

Mine, beyond the stage's:

| # | what I broke | result |
|---|---|---|
| B | the `removed=[...]` field alone deleted from the diff statement | **killed** - `theEmittedSkipLineNamesTheDays` fails at `#expect(diff.contains("removed=[-]"))`, 1 issue; the guard catches field-level regressions of the identifier lists, not only wholesale deletion |
| C | `failedCount=\(failures.count...)` hardcoded to `failedCount=\(0...)` | **SURVIVED** - 227 of 227 green; finding 2 |
| E | `for spec in specs` -> `specs.prefix(32)` in the reconcile loop (a scheduler that silently drops rungs before attempting them) | **killed twice** - the ceiling test at `(attempted.count -> 32) == 64` plus the pre-existing 200-subscription pin `(pending.count -> 32) == 64`, 3 issues; the expected set cannot shrink in lockstep with a dropping scheduler |
| - | grep for any canary matcher that would accept a sibling's token | the literal `otto.test.canary` survives only at the two mint sites; `requireDelivered` is the only checker and matches the full minted token, so no prefix-shaped `contains` remains |

The pristine re-run on the restored files was green on both hosts (227 and 127), and both restored files byte-compared identical.

## Findings

### 1 - P3, record accuracy. Item 7's "ten" site counts are the reader count wearing the wrong label: eleven emission sites and eleven `requireDelivered` call sites exist at the head

**The claim.**
`PROD-READINESS-5.md`, ITEM 7: "All ten `requireDelivered` call sites pass their own token" (`:440`) and "Ten emission sites and ten `requireDelivered` sites updated in eight files" (`:464`).

**What I executed.**
Enumerated both populations by grep at `cdb509e` and at `7b6df8c`, excluding the definitions and doc comments.
Emission sites: `NotificationActionLogTests` 4, `BoundaryLogTests` 2, `SchedulingLogTests` 2, OttoPersistence 3 - **eleven**, at both ends of the range, and all eleven were updated to bind the returned token.
`requireDelivered` call sites: **ten** at `cdb509e`, **eleven** at the head, because `BoundaryLogTests`' single check became two (`:72`, `:73`) - the per-category strengthening the same section correctly describes.

**Why it survived my attempt to dismiss it.**
I tried reading "sites" as "tests": there are indeed ten `OSLogStore`-reading tests and ten reads, and the neighbouring sentence's "the count stays ten" is true of readers.
But the sentence says sites, its sibling counts in the same bullet are literal ("eight files" is exactly eight), and the section's own point is per-site coverage - a future auditor who checks ten emission sites against this sentence stops one short, which is precisely how `reviews-4/REVIEW-AA92CA7.md` finding 3 ("four log-reading tests; it covers three") and finding 6 ("four deliberate file splits" over five names) happened.
The code is right; the census is wrong.

**What would make it right.** One correction naming the real numbers: eleven emissions and eleven checks in ten tests, ten reads.

### 2 - P3. `failedCount=` is pinned only at zero: hardcoding the field to 0 survives the full suite, and it is the one field item 3's drop rationale leans on

**The claim.**
ITEM 3, on dropping the aggregate entry: "The diff line's `failedCount=` keeps the total, and identifiers-never-counts (DECISIONS.md) is intact."
`reviews-4/REVIEW-AA92CA7.md` finding 1 had named `failedCount=` as the one real mitigation of the truncation era - the count an investigator checks names against.

**What I executed.**
Mutant C: `failedCount=\(failures.count, privacy: .public)` -> `failedCount=\(0, privacy: .public)` in the production statement, full host suite: **227 of 227 green**.
`git grep failedCount` confirms why: the field's only readers in the tree are item 6's `#expect(diff.contains("failedCount=0"))` - asserted on a CLEAN pass, where the mutant is indistinguishable from the truth - and the production source itself.
Nothing reads the field on a failing pass, the only regime where the total is non-zero.

**Why it survived my attempt to dismiss it.**
The identities are genuinely safe - the per-rung entries carry every name regardless, so no investigator loses a rung to this mutant, and a lying `failedCount=0` beside 64 failure entries is detectable by contradiction.
And item 6's non-scope sentence honestly declines to pin numeric values - but it names `pending=`/`desired=`, not `failedCount`, and item 3's record actively cites the field as what "keeps the total" after the aggregate was dropped.
A field the record leans on, guarded only in the state where it says nothing, is the R5-2 shape at one remove: correct, cited, and executable-guard-free where it matters.
The fix is one line inside a window that is already open - the ceiling test's own pass emits the diff line with `failedCount=64`, and the test already holds `lines` - or one clause extending item 6's non-scope sentence to own the gap.

## Explicit checks

- **The deleted test, against the never-weaken rule.** `noFailures` asserted one thing: `OttoLog.failures([]) == "-"`. That rendering was production-unreachable at `cdb509e` - the aggregate emission sat inside `if !failures.isEmpty`, so the dash was never logged - and the helper it exercised is deleted. The behavioural half the ledger routes to item 6 is genuinely asserted at emission level: `failedCount=0` plus the no-failure-entry check, both pinned to identifier 6_610, which the test owns. Nothing the deleted test guarded is unguarded now.
- **Is the ceiling test at least as strong as its predecessor?** Strictly stronger on every axis: 64 owned identifiers against one; byte-for-byte equality per entry (`$0 == "reconcile failed <id>=AddRefused"`) against prefix-plus-contains, so a truncated tail cannot satisfy it; the reason still asserted per rung; the per-rung-reason and type-never-value renderer assertions retained in `failedRungCarriesItsReason`. The expected set is calibrated from the fake's `addCalls` but anchored by `#expect(attempted.count == 64)` - the device-ceiling constant - so calibration cannot follow a shrinking scheduler (mutant E, killed twice).
- **The dropped aggregate, against DECISIONS.md's identifiers-never-counts.** The diff line's `removed=`/`added=` identifier lists are unchanged and now guarded (mutant B); every failure identity reaches the log on a complete entry; the drop's reason is recorded in the ledger and at the emission site. The grep surface is preserved - all 64 entries share the stable prefix `reconcile failed ` - so an investigator trades one truncated line for 64 complete greppable ones, plus `failedCount=` on the diff line, whose residual is finding 2.
- **Log volume.** Acknowledged in ITEM 3's cost bullet ("a worst-case failing pass emits 64 short error entries instead of one truncated one; a healthy pass emits nothing new"). By arithmetic the worst realistic entry is ~118 bytes (`reconcile failed ` 17 + a 70-char identifier with the longest kind, `conversionAnnouncement`, + `=` + a long error type name), an order of magnitude under the ~1024-byte budget; 64 entries is ~5.3 KB per failing pass. The 83-character figure the ledger records is exact for the test's `renewal`-rung shape (17 + 55 + 11).
- **Item 6's scope honesty.** The disclosed non-scope (numeric `pending=`/`desired=` values) is accurate; the identifier fields and `failedCount=0` are executable-guarded; the diff-line `#require` is pinned to the owned identifier 6_610 inside `added=[...]`, not a bare prefix, per the `reviews-4/REVIEW-6.md` lesson. Indices 9_100-9_163 and 6_610 are used nowhere else in the package - verified by grep in both underscore and plain forms.
- **Item 7's failure message.** Both probes' `requireDelivered` messages still name the environment causes (`OS_ACTIVITY_MODE=disable`, unreadable store, dropped entries), now alongside the ended masking; N4-18's notice-versus-error level asymmetry is untouched (`notice` in OttoUI, `error` in OttoPersistence, read from the source).
- **Range hygiene.** Six commits, all inside the declared R4; every message one short sentence with no body or trailer; the range touches two production files (both item 3's), eight test files, the user doc and the two record files; no `Package.swift`, no `.swiftlint.yml`, no workflow, no schema, no new target or dependency; R4's row in the ledger names each commit and its role, and the range's start is R3's recorded head.
- **Fabricated or unreproducible numbers.** None found. M2's 49/49/49 and M3's, M4's, M5's 1/1/1 reproduce with identical failing-test sets; M1's 64 reproduces on my single run; the five-dimension table is exact to the digit; the 15-named/1037-character stage-start figures are consistent with `reviews-4/REVIEW-AA92CA7.md`'s measurements at two earlier heads and with M2's arithmetic (64 - 15 = 49 issues).
- **Tests weakened.** None beyond the recorded deletion, which the first check above covers; the two renamed tests keep or strengthen every predecessor assertion; the eight item-7 files change only canary plumbing.

## Attempted refutations that did not become findings

- **Making the ceiling test pass while dropping rungs.** Mutant E (`specs.prefix(32)`): the `attempted.count == 64` pin and a pre-existing budget test both fail. A planner-level shrink is out of this test's jurisdiction and guarded by the planner suites; a reconcile-level shrink is what the test exists to catch, and it does.
- **Satisfying a per-rung assertion with a truncated tail.** Inexpressible against `==` equality; M1's aggregate revert - where the tail is truncated mid-identifier - fails all 64 assertions, not 49.
- **A sibling's canary standing in anywhere.** Both mint-without-emit mutants die 3 of 3 in full-suite runs; the full-token `contains` cannot match another test's UUID; no prefix-shaped matcher survives in the tree.
- **The item 6 guard catching only wholesale deletion.** Field-level mutant B is caught by the `removed=[-]` assertion; deleting `added=[...]` or `failedCount=` entirely would fail the identifier `#require` and the `failedCount=0` contains respectively (the first executed as part of M3's nil, the second read from the assertion). The one value-level gap is finding 2.
- **The `.serialized` persistence target hiding order dependence.** M5 failed identically on all three runs at the same call site; the pristine suite passed twice.
- **Sim-suite drift.** Three consecutive full runs byte-identical in counts (132/72/63, 9 known issues), the 9 composed of the same named sites as the R3 review recorded, minus nothing, plus nothing.

## What I could not check, and why

- **The stage-start reproductions at `e93dabb`.** The 1037-character aggregate naming 15 of 64, and the two deletions running green (228/228 and 127/127) before the fix - I did not rebuild at that commit. They are corroborated by `reviews-4/REVIEW-AA92CA7.md`'s equivalent measurements at `aa92ca7` and `80eeb97`, by `reviews-4/REVIEW-5.md` finding 2's green persistence deletion, and by my head-state mutants reproducing the same shapes from the other side.
- **The 12-of-12 flake dimension.** I made five pristine full host runs, all green at 227; twelve were not re-run, so the ledger's flake figure is sampled, not replicated.
- **`OS_ACTIVITY_MODE=disable` actually tripping the new message.** Read from source only; executing it was done by `reviews-4/REVIEW-5.md` against the shared-literal version, and the message path is the same `#require`.
- **CI-runner delivery, release configuration, a physical device.** Standing CANNOT ASSESS, as every prior round.
