# REVIEW-2 - round 5, stage 1 re-review (REJECT remediation), range `3173ba4..c94dbbd`

Reviewed head `c94dbbdec5a2f1c368a4ea095d5d17843791b675`, branch `prod-readiness-5/2026-08-15`.
The range contains three commits: `124ec44` (the finding-1 fix plus three host tests), `83f9717` (the finding-2 assertion rework, test-only), `c94dbbd` (ledger only).
I am the same reviewer that wrote `reviews-5/REVIEW-1.md` (REJECT), re-reviewing its remediation; this is the first REJECT cycle's re-review and the cap is two.
At review time the working tree matched the head: `git status --porcelain` empty, `HEAD == c94dbbd`, before this file was added.
All mutation and probe work was done in one detached worktree at `c94dbbd` under my own scratchpad; every mutated file was restored from a saved pristine copy and byte-compared, the worktree was clean before removal, and `git worktree list` now shows only the main tree.

verdict: PASS-WITH-FINDINGS

## Summary

**All six findings are closed, and I verified each by executing, not by reading.**
The starvation defect is fixed at the mechanism I named: `waiterCancelled` vacates the `queued` slot before cancelling an abandoned follow-up, my probe shape is now a shipped test, and deleting the fix (M7) kills that test on all three runs.
I probed the fix's new state machine three ways for a fresh window - a chain of two abandoned follow-ups in a row, abandonment followed by the predecessor finishing on a vacant slot, and sole-waiter cancellation of a promoted erstwhile follow-up - and all three behave correctly on three runs of three, so I could not find a window the vacate opens.
The flaky ordering assertion is replaced by a membership assertion of what the code actually guarantees, and the flake is gone by measurement: **36 of 36 suite-scoped simulator runs green at the head** (18 at my original narrow scope, which failed 7 of 18 at `c26b2a7`, and 18 at target scope), plus a full simulator run `** TEST SUCCEEDED **` at 130/72/56 with the 7 known issues.
The membership assertion still bites: a mutation that makes the background path hide its failed publish (the R4-2 regression shape) fails exactly the new `published.count` and nil-membership expectations.
The rebuilt seven-mutant battery reproduces: the failing-test set matches the ledger's table exactly for every mutant on every one of my 21 runs, the counts match to the digit for M2 through M6, and both of my previously surviving mutants (M5, M6) now die 3 of 3 at exactly the tests built to kill them.
The corrected ledger sentences say what the code does - "unordered", with the production coin flip stated - and the REVIEW RANGES section closes finding 6 with R0 declared honestly rather than papered over.
All five dimensions reproduce at the head: verify.sh exit 0 at 261/127/220 = 608, lint clean over 228 files, simulator TEST SUCCEEDED, harness 1/1/5 with the same citations, and every host run I made (10+) green.

What remains is small and carried as findings rather than grounds for a second REJECT: the production nondeterminism the remediation correctly disclosed now lives only in a ledger sentence, tracked by no work item, and two of the battery's recorded issue counts wobble by one on my host exactly as the ledger's own caveat predicts.
Nothing here warrants revert-and-DEFER: the defect I rejected for is gone, the flake I rejected for is gone, and the record now says true things.

## What I ran

All measurements at `c94dbbd`.
Host: macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0, simulator `<simulator-udid>`.

### The five dimensions at the remediation head

| dimension | ledger claims | measured here | result |
|---|---|---|---|
| `./scripts/verify.sh` | exit 0, 261/127/220 = 608 | **exit 0; 261 / 127 / 220 = 608** | exact |
| `swiftlint --strict` | clean, 228 files | **0 violations, 0 serious in 228 files** | exact |
| simulator suite, full | 130/72/56, 7 known issues, `TEST SUCCEEDED` | **130 / 72 / 56, `with 7 known issues`, `** TEST SUCCEEDED **`** | exact |
| non-Gregorian harness | 1 / 1 / 5, same citations | **1 / 1 / 5** (220-test bundle) | exact |
| flake | 12 of 12 host runs | **4 of 4** dedicated runs plus the worktree's baseline run and the verify.sh leg, all green, 220 tests each | clean (smaller sample, disclosed) |

### Finding-by-finding verification

| finding | remediation claim | executed here | result |
|---|---|---|---|
| 1 (P2) | slot vacated; probe shape shipped; M7 dies | shipped test green in every run; **M7 fails exactly the two recorded tests on 3 of 3 runs**; three new-window probes (below) pass 3 of 3 | **closed** |
| 2 (P2) | membership asserted; 18/18 scoped; full suite green | **18 of 18** at my original narrow scope (`SchedulingGateIntegrationTests`, was 11 of 18 green at `c26b2a7`), **18 of 18** at target scope, full suite `TEST SUCCEEDED`; M8 falsification (below) fails the new assertions | **closed** |
| 3 (P3) | seven mutants, exact diffs, stable failing sets | all seven applied from the ledger's exact-change column; **failing-test sets identical to the table on every one of 21 runs**; counts exact for M2-M6, M1 84/85/84 vs recorded 85/85/85, M7 4/3/3 vs 3/3/3 | **closed** (finding 2 below on the wobble) |
| 4 (P3) | latest-joiner-arguments pinned; M5 dies at that test | **M5 fails only "the follow-up runs with the most recent joiner's arguments", 1 issue, 3 of 3 runs** | **closed** |
| 5 (P3) | staged release; M6 dies every run | **M6 fails only "a caller during the follow-up pass queues behind it", 3 issues, 3 of 3 runs** | **closed** |
| 6 (P3) | REVIEW RANGES section | R0/R1/R2 declared; R0's non-review stated honestly and flagged for terminal reconciliation; R2 includes `3173ba4`, so no round-5 commit now falls outside every range | **closed** |

### My own falsifications and probes, beyond the remediation's

| # | what I did | result |
|---|---|---|
| R2-A | chain of corpses: two successive follow-ups abandoned while pass 1 still runs, then a live caller | **correct 3 of 3**: live caller gets pass 2, both cancelled callers get `CancellationError`, `passes == 2`, `peak == 1` |
| R2-B | abandonment, predecessor finishes on the vacant slot, then a caller | **correct 3 of 3**: fresh immediate pass, corpse never touched the base scheduler |
| R2-C | sole-waiter cancellation of a PROMOTED follow-up mid-run (no shipped test covers the promoted case) | **correct 3 of 3**: the pass is cancelled, the gate reopens, the next caller gets a fresh pass |
| M8 | `onOutcome?(outcome)` in `handleBackgroundRefresh` guarded with `if let outcome` - the background hides its failed pass, R4-2's regression shape | **caught**: `published.count → 1` and the nil-membership expectation fail, 2 issues - the membership assertion is not satisfiable by this broken implementation |

The M8 check answers the re-review's standing question about finding 2's rework: the new assertion set (`count == 2`, exactly one non-nil with `scheduledCount == 1`, at least one nil) cannot be satisfied by two outcomes, two nils, or a swallowed publish, and the behavioural assertions (`spy.passes == 1`, `cancelledPasses == 0`, `completions == [false]`) are unchanged.

### The remediation's own new surface, read line by line

- The vacate is identity-guarded (`pass === queued`), so a fresh follow-up occupying the slot cannot be vacated by the corpse's late cancellation.
- The corpse's task still runs after the predecessor, finds `pass !== queued`, skips promotion, and dies at `checkCancellation` without touching `inFlight` or the base scheduler - which is what probes R2-A and R2-B confirm by execution.
- The deleted probe (`probeQueuedTaskIsCancelled`) watched a mechanism the fix removed; the two shipped tests that used it now settle on `probeQueuedWaiters == 0`, with every behavioural assertion unchanged - I diffed both tests and the ledger discloses the modification.
- The spy's staged release (`releasedUpTo`) is monotone under `max`, keeps `release()` as `Int.max`, and preserves the semantics of every pre-existing `.held` test.
- The three new host tests can each fail and do fail under the battery's mutants (M5, M6, M7 respectively, plus M1/M2 collaterally).

## Findings

### 1 - P3. The disclosed production coin flip is tracked by no work item

**Evidence.**
`PROD-READINESS-5.md:162` now states, correctly: "the store's final published state after this scenario is a coin flip between the coverage outcome and the failed-pass state, in the test and in production alike."
That is a user-visible nondeterminism: after a background expiration during a foreground pass, Today either shows the earned coverage sentence or the failed-pass state depending on which continuation resumes last, and `:209` records the deliberate decision not to enforce an order as out of this item's scope - which is right.
But the decision's residue lives only in these two sentences: the work list has no row for it, NEXT ROUND still "Opens empty" (`:270`), and nothing obliges a later round to either enforce an order or accept the flip on the record.
The round-4 lesson this repeats is N4-3's original shape: a correctly-scoped deferral that no entry carried, which cost a round to rediscover.

**What would make it right.** One NEXT ROUND entry naming the choice (order the two publishes, or accept and document the flip as the R4-2 contract's cost), at P3.

### 2 - P3. Two of the battery's issue-count columns are still samples, and reproduce as the caveat predicts rather than as printed

**Evidence.**
The battery table (`PROD-READINESS-5.md:218-226`) records M1 at "85 / 85 / 85" and M7 at "3 / 3 / 3".
My three runs of the same exact diffs: M1 **84 / 85 / 84**, M7 **4 / 3 / 3**; M2 through M6 reproduce to the digit, and every failing-test set matches on every run.
The ledger's own sentence carries the caveat ("both are recorded because the standing lesson is that they need not be" stable), so nothing here is false - but a reader of the table alone will still take 85/85/85 as a property, which is the exact failure mode finding 3 was about, one caveat-sentence away from repeating.

**What would make it right.** Mark the issue-count column itself as sample-only (a header word suffices), or record the observed range instead of three identical samples.

### 3 - P3, record accuracy. The remediation misnames my contention shape

**Evidence.**
`PROD-READINESS-5.md:210` describes its 18-run evidence as "`-only-testing:OttoUITests`, the reviewer's contention shape".
My 18 runs in `reviews-5/REVIEW-1.md` were scoped one level narrower, to `-only-testing:OttoUITests/SchedulingGateIntegrationTests`.
Materially moot - I re-ran both shapes at this head, 18 of 18 green each - but the sentence attributes a measurement shape to my review that my review did not use, and this ledger's history is precisely of small unverified attributions compounding.

**What would make it right.** Say "target-scoped, a heavier-contention variant of the reviewer's suite scope" or re-cite the narrow scope; no re-measurement needed, mine is on this page.

## Explicit checks

- **Fabricated or unreproducible claims.** None found. Every number I re-derived matched or fell inside the ledger's own stated tolerance; the two count wobbles are finding 2 and are disclosed as possible by the ledger itself.
- **Tests weakened.** The ordering assertions were replaced by membership assertions that are weaker in ordering and equal in guarantee; M8 proves they still catch the R4-2 regression shape, and every behavioural assertion in both modified tests is unchanged. No other test changed; the coordinator's nine tests are untouched in this range.
- **A new window opened by the fix.** Probed three ways (R2-A, R2-B, R2-C), none found; the identity guard and the corpse's promotion-skip are correct by execution, not just by reading.
- **Scope creep.** The range touches one production file (eleven lines, all in `waiterCancelled` plus one probe deletion), two test files, and the ledger. No `Package.swift`, no lint config, no workflow, no schema, no user-facing copy.
- **`OSLogStore`.** No reader added; the count stays ten.
- **The cap arithmetic.** This is cycle one's re-review; the ledger says so at `:200`; the R2 row correctly includes my own review commit `3173ba4` so no round-5 commit is outside every range; R0 remains reviewed-by-measurement only, self-flagged for terminal reconciliation, and I did not re-review it here.
- **Restorations.** `cmp` clean after every mutant and after M8; both probe files deleted with the worktree; the main tree was never modified except by this file.

## What I could not check, and why

- **R0's contents beyond its diffstat.** Declared out of my range by the ledger and left to the terminal reconciliation it is flagged for.
- **The production coin flip's field frequency.** Requires a real expiration racing a real foreground pass on a device; finding 1 records the tracking gap instead.
- **Release configuration, physical device, real `BGAppRefreshTask`.** Unchanged constraints from every prior round.

## Verdict justification

PASS-WITH-FINDINGS.
Both P2s I rejected for are closed by the mechanism I asked for and verified by execution: the starvation is structurally gone and guarded by a test that dies with the fix, and the flake is gone across 36 scoped runs plus a full green suite where the head previously failed 7 of 18 and my one full run.
The rebuilt battery is the strongest falsification record this project has shipped - exact diffs, stable failing sets that reproduce identically on my host, and my two surviving mutants now die at purpose-built tests - and my three fresh attempts to break the new state machine failed.
The three residual findings are record-hygiene at P3, none touches code correctness, and none justifies the revert-and-DEFER that a second REJECT would force on a fix that is now demonstrably right.
Item 1 (N4-7 + N4-3) is RESOLVED on this evidence.
