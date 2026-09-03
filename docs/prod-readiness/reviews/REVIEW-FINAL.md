# REVIEW-FINAL — the complete run, `406a5a6..221723f` on `prod-readiness/2026-08-10`

**VERDICT: PASS-WITH-FINDINGS**

Eighteen commits, twenty-three files, no SwiftData schema change anywhere, no prohibited action by the builder anywhere, and nothing worse than `reviews/BASELINE.md` on any axis I could measure.
Every frozen P0/P1 is in one of the three terminal states with an artifact behind it, and I re-derived the closing numbers rather than reading them.

The run is not rejected, and I want to be precise about why it survives its own worst moment.
Pass 2 shipped a fix that would have converted a working non-Gregorian device into a silently dead one; Review 2 caught it, the builder reverted it and deferred F1 with the discovered scope.
That is the loop working, and the ledger says so plainly at `PROD-READINESS.md:243` rather than burying it.

The findings below are seven, none of them a defect in what the committed code *delivers*.
They are, in order: a P1 residual of this run's own user-visible change that is filed where nobody will look for it; a prohibited action inside the review trail; a systematic review blind spot that swallowed the two most important remediation commits in the run; one small error-hiding regression introduced by pass 4; and three ledger-accuracy defects.

All of them go to **NEXT ROUND** except finding 4, which is a regression from this run's own change and is recorded as such.

---

## 1. Verification re-derived here, not read from any artifact

Every number below was produced by this review on this host, at HEAD `221723f`.

| measurement | `BASELINE.md` claims | ledger claims at HEAD | re-derived here | result |
|---|---|---|---|---|
| `scripts/verify.sh` | exit 0; OttoDomain 246 / OttoPersistence 112 / OttoUI 168 = **526**; lint clean `--strict` | exit 0; 246 / 113 / 174 = **533**; lint clean | **exit 0**; `== VERIFIED: 221723f78fbe3911fa6827f96a1aca81a0363408 builds, tests, and lints from a clean clone`; OttoDomain **246**, OttoPersistence **113**, OttoUI **174**, total **533**; `swiftlint --strict` clean | ✅ both reproduce exactly |
| simulator suite (`xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"`, from `Packages/OttoUI/`) | 19 tests, 7 known issues, `** TEST SUCCEEDED **` | 20 tests, same 7 known issues | exit 0, `** TEST SUCCEEDED **`; `Test run with 101 tests in 18 suites` / `65 tests in 11 suites` / `20 tests in 3 suites … with 7 known issues`, all seven in `EmptyStateTests` at `:211`, `:235`, `:254`, `:295` | ✅ headline reproduces; see finding 6 |

Against `BASELINE.md`: **+7 host tests, lint clean, no rule relaxed** (`.swiftlint.yml` is untouched by the range). Nothing regressed.

**No SwiftData schema change, proved rather than asserted.**
`git diff --name-only 406a5a6..HEAD -- Packages/OttoPersistence/Sources/` is **empty**. No model, no `OttoSchemaV*`, no `OttoMigrationPlan`, no `OttoContainerFactory`. The only `OttoPersistence` change in the whole run is two test files. V3 is frozen and stayed frozen.

**No prohibited action by the builder.**
`git diff --name-only 406a5a6..HEAD -- .github/ docs/ DECISIONS.md README.md project.yml .swiftlint.yml scripts/ '**/Package.swift' Packages/OttoDomain/` is **empty** — no workflow, no narrative document, no dependency, no lint config, no language-mode or SDK change.
`git merge-base --is-ancestor 406a5a6 HEAD` succeeds (no rewrite); `git reflog` shows eighteen ordinary `commit` entries and one ordinary `revert`, no rebase/amend/reset; `git show-ref` has `refs/remotes/origin/main` still at `406a5a6`; `git branch -a --contains HEAD` returns only `prod-readiness/2026-08-10` (not pushed); `git tag -l` is empty.
No Otto artifact in `<backup-dir>` carries an mtime inside the run window (19:16–21:05) — the Gate 3 export, its VERIFIED twin and both container backups are all still Aug 8. (The directory's own mtime moved at 21:00 and its `.DS_Store` at 20:35; neither is attributable to this run and I am recording that rather than making a finding out of it.)

**Reviewer output was never edited.** `git log --follow` over each of `BASELINE.md`, `REVIEW-0.md`, `REVIEW-2.md`, `REVIEW-3.md`, `REVIEW-4.md`, `REVIEW-5.md` returns exactly one commit each. No verdict was touched after it landed.

**No work expanded past the frozen list.** Every one of the twelve changed source/test files traces to a frozen finding: `ExportService.swift` → F6; `NotificationActionHandler.swift` → F4 + F2; `NotificationCoordinator.swift`, `NotificationStatusStore.swift`, `OttoApp.swift` → F3; `NotificationScheduler.swift` → F5; `ScheduleOutcome.swift`, `TodayView.swift` → R0-1; `OttoLog.swift` → F2; the four test files guard those. No screen, toggle, export field, model, property, schema version, config key, or line of user-facing copy was added. The only user-visible changes are a subtraction (a footer withheld in two more cases) and a correction of an existing rung's interruption level to what `PlannedReminder.Kind.isTimeSensitive` already said it should be.

**No post-freeze finding was folded into the frozen work list.** The eight items at `PROD-READINESS.md:154-163` are F4, R0-1, F3, F5, F2, F6, F1, F7 — all from Review 0 or earlier. R0-1 entering the list is legitimate: it was discovered *by* Review 0, which is the freeze point, not after it.

## 2. Falsification of the three guards no prior reviewer saw

Findings 1–3 of Reviews 3 and 4 were remediated in commits that fell outside every subsequent review's range (finding 3 below). I broke each one myself and reverted it; `git status --porcelain` was empty before and after each.

**`c49ece2` — F6's end-to-end guard.** `OttoStore.restore` reduced to `try restoreThroughMainSave(snapshot, at: instant, markingDirty: false)` with the `reconstructWatermarksNow()` call deleted, then `swift test --package-path Packages/OttoPersistence`:

```
✘ Test "restoring into an EMPTY store reconstructs from the imported ledger; keep leaves it nil"
   recorded an issue at DataTransferTests.swift:343:9
✘ Test run with 113 tests in 23 suites failed after 2.188 seconds with 1 issue.
```

**One** issue out of 113 tests, which is the point: this is the only test in the tree that binds `.reconstruct` to a watermark value through `restore` itself. Review 3's finding 1 was real and `c49ece2` genuinely closes it.

**`c140685` — R0-1's guard.** `TodayView.swift:66` reverted to `if input.scheduleOutcome != nil,`:

```
✘ Test "a pass that failed some subscriptions' ledgers withdraws the coverage claim from Today"
   TodaySectionPlanTests.swift:40:9: !plan(scheduleOutcome: try healthyOutcome(ledgerFailures: [UUID()])).contains(.coverage)
✘ Test run with 174 tests in 30 suites failed after 0.924 seconds with 1 issue.
```

Review 4's finding 1 — that reverting this exact expression left all 173 tests green — no longer holds. The gate is reachable and pinned where it is applied.

**`c140685` — the repaired permission assertion.** `permission = await client.permission()` deleted from `NotificationStatusStore.swift:52`:

```
✘ CoverageHonestyTests.swift:70:9: Expectation failed: (store.permission → .authorized) == .denied
```

Review 4's finding 3 (an `#expect` that held whether the refresh happened or not) is genuinely closed: the store's seeded permission and the client's answer now differ, so the assertion has something to distinguish.

**Fabricated or unreproducible findings across the whole trail: none found.** Every claim I spot-checked against the tree held, including the one substantive factual assertion in the unreviewed final commit — `PROD-READINESS.md:227`'s claim that §9a's "§5.4 paused-cancellation is specified but not implemented" row is stale. Confirmed: the row is live at `docs/Subscription-Tracker-Spec.md:918` while `CancellationSectionView.swift:165-190` renders `resumeDatePrompt`, `:258` renders the `.awaitingResumeDate` badge, and `AppModel.swift:195` wires `supplyPausedResumeDate` through `SubscriptionFlowService.swift:321`.

---

## Findings

### 1. P1 — the run's own net effect on an authorized user is an open P1, and it is filed in the one section the termination rules do not point at

**severity: P1** for the state of the product. I am **not** asking for a code change: Review 4 rated this P1, reached the right disposition, and I agree with it. The finding is that the disposition is unfindable.

**evidence.**
`PROD-READINESS.md:140` carries R4-1 at P1: after this run, `TodaySection.plan` emits `.notificationStatus` only when `permission != .authorized` (`TodayView.swift:46-48`) and `.coverage` only when `canClaimCoverage` (`:66-67`), so for an **authorized** user whose engine has failed on every pass since install, Today is byte-identical to a healthy one. I confirmed both gates at HEAD. That is silence on the one screen whose stated job is to never fail silently (`NotificationStatusStore.swift:6-9`), produced by this run's own F3 + R0-1 changes.

Where it sits: `## DEFERRED` begins at `PROD-READINESS.md:115` and `## THE FROZEN WORK LIST` at `:148`, so R4-1 at `:140` is inside DEFERRED. `## NEXT ROUND` (`:179-186`) lists R0-6, R0-7, R0-5/R0-9/R0-10/R0-11, F8–F11 and two Review-0 §4 items — **R4-1 is not among them.** The Status table (`:192-201`) marks F3 and R0-1 **RESOLVED** with no cross-reference to it; F3's cell points to R4-2 instead.

So the document's summary of this run reads "every frozen P0/P1 is in a terminal state" while the state those closures produced is itself an open P1 that appears in neither the Status table nor NEXT ROUND. A reader who follows the termination rules to find what this run discovered and did not fix will not find it.

**why the builder missed it.** The builder did not miss the mechanism — `c7bfe46`'s closing paragraph states it, and Review 4's finding 4 already caught it living only in a commit message. The correction moved it into the ledger, but into DEFERRED, which is the section the scope constraint defines for fixes that would require a new feature. R4-1 *does* need new copy, so DEFERRED is not an unreasonable read — but the termination rules define a different destination for post-freeze findings, and choosing the scope constraint's section over the termination rules' section put the run's most consequential residual in the least-read place. The Status table then closed F3 and R0-1 without a pointer, because a "RESOLVED" cell has no slot for "and here is what the resolution cost".

**routing: NEXT ROUND.**

### 2. P2 — a prohibited action was taken inside the review trail, and the first reviewer to take it cited its output as proof that no prohibited action occurred

**severity: P2.** Read-only, nothing changed, and the answer it produced matched the local ref — but "No network calls of any kind" is unconditional, and the point of an unconditional prohibition is that its violations are not graded by outcome.

**evidence.**
`git config --get remote.origin.url` is `git@github.com:8C9D/otto.git` — a real remote over SSH, not a local path. `git ls-remote origin` therefore contacts it.

`reviews/REVIEW-4.md:38`: *"`git ls-remote origin` still shows `refs/heads/main` at `406a5a6`"*.
`reviews/REVIEW-4.md:236`, inside the bullet headed **"No prohibited action"**: *"`git ls-remote origin` still has `main` at `406a5a6` … no device contact, **no network call**, nothing in `<backup-dir>` touched."*

That sentence asserts no network call was made, in the same clause as the network call, using its output as the evidence. Review 5 ran the same command, recognised it, and disclosed it properly at `reviews/REVIEW-5.md:206`.

One further inaccuracy in the disclosure itself: Review 5 says *"the two prior reviews ran the same command."* Review 4 demonstrably did. Review 3 (`reviews/REVIEW-3.md:153`) and Review 0 (`reviews/REVIEW-0.md:30`) phrase the same check as `origin/main` / "no remote branch contains HEAD", which is satisfiable from `refs/remotes/` with no network access, so the attribution to two prior reviews is unverified from the artifacts.

The correct check needs no network at all: `git show-ref` reads `refs/remotes/origin/main`, and `git branch -a --contains HEAD` proves nothing on a remote contains the work. Both are what I used.

**why the builder missed it.** Not the builder's to miss — this is a reviewer defect, and the contract routes reviewer conduct to the final review. It survived because the prohibited-action checklist was executed as a checklist: each reviewer verified the *subject* of the review against the prohibitions and did not turn the same list on its own commands until Review 5 did.

**routing: NEXT ROUND.**

### 3. P2 — three code-touching commits and the ledger's entire closing section were never inside any review's diff range, and two of them are the remediations the reviews demanded

**severity: P2.** No defect was found in them — I falsified all three guards in §2 and they hold — but a run whose contract is "every stage ends with an adversarial review" left its most important repairs unreviewed by construction, and that is only visible from here.

**evidence.**
`reviews/REVIEW-4.md:1` scopes itself to `c49ece2..d3eb18a`; `:24` uses `c49ece2` only as a parent to count tests at. `reviews/REVIEW-5.md:1` scopes itself to `c140685..58695c2`; `:24` does the same for `c140685`.
So each remediation commit became the *parent* of the next review's range and fell outside its diff:

- **`c49ece2`** (+61 to `DataTransferTests.swift`, +6/-2 to `RestoreDirtyFlagTests.swift`) — the end-to-end empty-store proof Review 3's finding 1 demanded, i.e. the only committed evidence that F6's fix does what F6 claims.
- **`c140685`** (`TodayView.swift`, `CoverageHonestyTests.swift`, `TodaySectionPlanTests.swift`) — the reachable guard Review 4's finding 1 demanded for R0-1, plus the repair of Review 4's finding 3.
- **`412999b`** (`NotificationActionTests.swift`, +17/-5) — the correction of the false justification Review 5's finding 2 measured.
- **`221723f`** (+54 to `PROD-READINESS.md`) — the entire Status table, the "Verification at HEAD" numbers, and the whole PRIOR-KNOWN COMPARISON. Every closing claim this run makes about itself landed after the last stage review.

The two most serious verification findings of the whole run (F6 has no end-to-end guard; R0-1 has no guard at all) were therefore closed by commits no adversarial reviewer read.

**why the builder missed it.** The range convention is `parent..head`, and a remediation landed between a verdict and the next pass is always the next range's parent. Nothing in the per-pass rules says a post-verdict remediation is itself a stage, so each one inherited the next reviewer's baseline role instead of its subject role. The fix is a convention, not work: a remediation commit belongs inside the next review's range, or gets a short review of its own.

**routing: NEXT ROUND.**

### 4. P2 — REGRESSION from pass 4: `reconcile` now attempts every rung and then discards every failure reason but the first

**severity: P2**, and it is a regression from this run's own change rather than a NEXT ROUND finding, because the information it loses did not exist before pass 4. It degrades diagnosability only — the device ends every pass holding a strict superset of what the old code left it — which is why I am recording it rather than asking for a revert of a fix that is otherwise correct and correctly guarded.

**evidence.**
`NotificationScheduler.swift:185-190`:

```swift
var failures: [(id: String, error: any Error)] = []
for spec in specs where pendingByID[spec.identifier] != spec {
    do { try await client.add(spec); added.append(spec.identifier) } catch {
        failures.append((spec.identifier, error))
    }
}
```

`:200` logs `failed=[\(OttoLog.list(failures.map(\.id)), privacy: .public)]` — **identifiers only**.
`:203` is `if let first = failures.first { throw first.error }` — **the first error only**.

So the errors of rungs 2..n are collected and dropped: they reach neither the log nor the caller. Before `c7bfe46` those adds were never attempted, so nothing was lost; after it they are attempted, they fail, and the reason is discarded. On a device where two causes coexist — the 64-slot ceiling refusing one rung, something else refusing another — an investigation sees one error type plus a list of identifiers and cannot tell that a second cause exists at all. The catch-all `catch` also absorbs a `CancellationError` from `add` into `failures` and continues the loop, in a pass whose cancellation checkpoints (`:113`, `:136`) exist because Gate 2 found a pass running on past its expiration.

This is the ledger's own R4-3 complaint (`PROD-READINESS.md:142`, `ledgerFailures` reaching the log as a bare count) in a second location, introduced this run rather than inherited.

**why the builder missed it.** F5's finding text is about *starvation* — "one rejected `add` silences every rung ordered after it" — and the fix column says "collect per-spec failures and continue … report them in `ScheduleOutcome`". The first half was implemented and guarded; the second half was reduced to identifiers in a log line and a single rethrow, and nothing in the finding asked what a *second* distinct failure would look like afterwards. Review 4 checked that F5 "does not relocate the bug or hide an error" against the rethrow and the log's `added`/`failed` split, which is true of the first error and silent about the rest.

**routing: regression from this run's own change. Recorded, not remediated — the remaining passes are closed and the defect costs no delivery.**

### 5. P2 — every post-freeze reviewer finding was appended to DEFERRED rather than NEXT ROUND, and two of them state no reason at all

**severity: P2**, bookkeeping — the information is all in the document, in the wrong section.

**evidence.**
The termination rules: *"Findings discovered after Review 0 … are appended to NEXT ROUND."*
`## NEXT ROUND` (`PROD-READINESS.md:179-186`) contains R0-6, R0-7, R0-5/R0-9/R0-10/R0-11, F8–F11, and two items from `reviews/REVIEW-0.md` §4 — **all of them pre-freeze or Review-0 findings.**
Every genuinely post-freeze reviewer finding is instead under `## DEFERRED` (`:115-146`): **R5-1** (`:137`), **R5-2** (`:138`), **R4-1** (`:140`), **R4-2** (`:141`), **R4-3** (`:142`), **R3-1** (`:144`).

The charge requires every DEFERRED item to state a reason. R3-1 does (*"Post-freeze discovery, so recorded rather than fixed"*), R4-1 does (*"new user-facing copy, which the scope constraint forbids"*), R5-2 does (cost and log-daemon dependence). **R4-3 (`:142`) and R5-1 (`:137`) state none** — they are descriptions of a defect with no disposition attached.

**why the builder missed it.** DEFERRED and NEXT ROUND both mean "not fixed in this run", and the two governing documents point at different sections for it: the scope constraint says *"log it under DEFERRED with reasoning"*, the termination rules say *"appended to NEXT ROUND"*. Post-freeze findings whose fix would also need a feature satisfy both descriptions, so the whole class was filed under the first one and the reason-per-item discipline of DEFERRED was applied to only four of the six.

**routing: NEXT ROUND.**

### 6. P2 — three of the ledger's closing claims about HEAD are inaccurate

**severity: P2** each; grouped because they are the same failure and all three live in the run's final, unreviewed commit.

**evidence.**

(a) `PROD-READINESS.md:207` — *"**nothing removed**, nothing weakened"*. A test was removed. `git show c7bfe46:Packages/OttoUI/Tests/OttoStoresTests/CoverageHonestyTests.swift | grep -n "@Test"` returns two, at `:49` and `:68`; the file at HEAD returns one, at `:50`. `c140685` deleted *"a pass that failed some subscriptions' ledgers may not claim coverage"*. The deletion is **correct** — Review 4's finding 1 showed it restated `ledgerFailures.isEmpty` through its own alias, and a stronger test replaced it in `TodaySectionPlanTests` — and net counts are unaffected. The sentence is still false as written, in the one paragraph whose job is comparing HEAD to BASELINE.

(b) `PROD-READINESS.md:205-207` — *"+1 simulator test"*. The `OttoUI-Package` scheme runs three test runs, not one. At HEAD I measured `101 tests in 18 suites` / `65 tests in 11 suites` / `20 tests in 3 suites … 7 known issues`; `reviews/BASELINE.md:203-223` records only the last (`19 tests in 3 suites`) as its headline, though `reviews/REVIEW-5.md:23` recorded all three (baseline 97 / 64 / 19). So the real delta is **+6**, and the baseline's simulator figure understates that command's coverage by roughly 161 tests. The comparison is measured against a number that never described the whole run.

(c) `PROD-READINESS.md:62-68` — several findings' evidence no longer resolves at HEAD, because this run's own commits moved the lines:

| finding | ledger cite | what is actually there at HEAD |
|---|---|---|
| F2 | `NotificationCoordinator.swift:234` (`try? await handler.handle`) | `:234` is `didReceive response: UNNotificationResponse`; the `try?` is `:240` |
| F5 | `NotificationScheduler.swift:180-183` (the add loop) | `:180-183` is the comment block; the loop is `:186-190` |
| F3 | `TodayView.swift:187-193` (the coverage footer render) | `:187-193` is the doc comment and `coverageSection`'s opening lines |
| R0-1 | `TodayView.swift:61-63, 113` (the gate, the mapping) | `:61-63` is the `.next30Days`/`hasLater` block; the gate is `:66-67` and the mapping `:118` |

`reviews/REVIEW-5.md:183` flagged the F2 drift specifically (*"F2's evidence cite … is now `:240` after pass 4"*) and it was not carried into the ledger. This is the contract's own named hazard — evidence citations that do not say what they are claimed to say — and R0-3 already corrected five citations of exactly this class earlier in the run, so the standard was established and then not re-applied at the end.

**why the builder missed it.** All three are in `221723f`, the run's last commit, written after the final stage review and therefore reviewed by nobody until now (finding 3). The per-pass rules are written per-commit and carry no step for re-validating the ledger's own claims against the tree the run produced; the citations in particular were fixed once, in response to R0-3, and then treated as settled while five subsequent commits moved the lines underneath them.

**routing: NEXT ROUND.**

### 7. P2 — `reviews/BASELINE.md` is not reproducible as written, and the ledger repeats its command without the correction

**severity: P2.** Recorded because a baseline that cannot be re-run as recorded is weaker evidence than its exit code suggests, and this one is the measuring stick for the entire run.

**evidence.**
`reviews/BASELINE.md:12` records the simulator command as run against the repo. `reviews/REVIEW-2.md:24-28` measured that it fails from the repo root — `xcodebuild: error: The project named "Otto" does not contain a scheme named "OttoUI-Package"`, exit 65 — because the generated `Otto.xcodeproj` shadows the package, and only reproduces from `Packages/OttoUI/`. Reviews 3, 4 and 5 each silently carried the correction in their own tables (*"run from `Packages/OttoUI/` per REVIEW-2's note"*). I had to do the same to get the run in §1.

`PROD-READINESS.md:27` still lists `xcodebuild test -scheme OttoUI-Package -destination "id=<sim>"` unqualified, and `:205` states the HEAD simulator result without saying where it must be run from. Editing `BASELINE.md` after the fact would be wrong — it is a captured artifact — but the ledger is the live document and had four opportunities to carry the correction forward.

**why the builder missed it.** Review 2's note is filed under "Verification re-run", not under its Findings, and marked *"recorded, not a stage finding"* — so it was never routed anywhere, and each subsequent reviewer independently rediscovered and locally worked around it rather than the ledger absorbing it once.

---

## Checked and found clean (recorded so severity is not inflated by omission)

- **Every RESOLVED has an artifact.** F2 → `58695c2` (with its boundary stated: host-only unified-log emission, UNVERIFIED on device, no executable guard); F3 → `c7bfe46`; F4 → `c7bfe46` (UNVERIFIED on hardware, stated); F5 → `c7bfe46`; F6 → `b15b0a6` + `c49ece2`; R0-1 → `c7bfe46` + `c140685`. Every cell carries a SHA — Review 5's finding 3 about F2's missing SHA was closed at `412999b`.
- **Every DEFERRED states a reason**, except R4-3 and R5-1 (finding 5). F1's is the longest and best in the document: it names the discovered scope, the measurement that overturned the original fix (`nextTriggerDate()` nil under `y=2026, calendar=.buddhist`), and the required change for whoever picks it up, including the `LiveNotificationClient` half no frozen finding cited.
- **Stage 0 assumptions that later evidence contradicted: one, and it was handled correctly.** `PROD-READINESS.md:62`'s original F1 blast-radius claim ("scheduled centuries away and never fire") was contradicted first by Review 0's own measurements (R0-2: Japanese, Islamic, ROC and Persian resolve to the *past*) and then more deeply by Review 2's `UNCalendarNotificationTrigger` measurement, which showed the two errors *cancel* on an untouched device. Both amendments are in the ledger, and the second is the reason F1 is DEFERRED rather than shipped. `ASSUMPTIONS 1` (Gregorian device) was never contradicted and remains correctly labelled undeterminable.
- **No pattern of fixes drifting toward scope expansion.** The opposite: the diff *narrows* over the run. Pass 2 touched five files and was reverted; pass 3 touched two; pass 4 touched eleven but every one of them traces to a frozen finding; pass 5 touched four; the three post-review remediations touched tests, one expression, and comments. The largest single addition in the run is a test.
- **No fix relocated a bug.** F6's fix routes the empty-database case into `reconstructWatermarksNow`, which carries R0-6's resurrection hole — but on an empty store `.reconstruct` is strictly additive relative to `.keep` (Review 3 measured it; I re-verified the composition falsifies correctly in §2), so nothing was moved. F3/R0-1 withdraw a false statement rather than moving it, at the cost recorded as finding 1.
- **No error handling that hides an error**, other than finding 4. `NotificationActionHandler.handle` rethrows the original value unchanged after logging (`NotificationActionHandler.swift:80`); `reconcile`'s throw is raised *after* its log line so the `added`/`failed` split is on record; `NotificationStatusStore`'s catch publishes `nil` rather than swallowing. The coordinator's `try?` at `NotificationCoordinator.swift:240` is deliberately untouched, which is right — a `UNUserNotificationResponse` has nowhere to report to, and that is exactly why F2's log line exists.
- **No tests that pass for the wrong reason among the guards I could reach.** Six of the seven new tests fail for the right reason and for that reason only, verified either by a prior review's reproduction or by my own (§2). The seventh — F2's log emission — has no guard, which is disclosed in the code comment at `NotificationActionTests.swift:110-128`, in the ledger's F2 cell, and in NEXT ROUND as R5-2, with the working technique (`OSLogStore(scope: .currentProcessIdentifier)`) named.
- **The one test-count claim that could have hidden a weakening does not.** OttoUI went 168 → 169 → 173 → 173 → 174 across the run; the flat step is `c140685`, where one test moved from `OttoStoresTests` to `OttoUITests` and got stronger in the move (finding 6a).
- **`c49ece2` is lint-clean by composition**, though no reviewer checked it: its two files are unchanged from that commit to HEAD, and HEAD is clean under `--strict`. The one genuine lint regression in the run (`c7bfe46`, three `--strict` violations) was caught and repaired inside its own stage at `d3eb18a`, and I confirmed `d3eb18a`'s reshape of the add loop is behavior-identical to what it replaced.
- **The contamination disclosure holds and was not quietly walked back.** `scripts/verify.sh` still prints `docs/next-wave.md` in full — my own run of it printed the `⛔ RESUME HERE` section including both named defects — and the PRIOR-KNOWN COMPARISON reports *"independent rediscovery of known open defects: zero out of two"* rather than claiming credit. That is the honest number and the run states it.

## What this verdict means

**PASS-WITH-FINDINGS.** The work list froze at eight, closed at eight, and every closure I could reach falsifies correctly — including the two that no stage reviewer ever read. The schema is untouched, no feature was smuggled in, and the one pass that would have made a real user strictly worse off was rejected, reverted and deferred with the scope its own failure revealed.

What this run leaves behind, in one sentence: an authorized user whose scheduling engine fails on every pass now sees a Today screen indistinguishable from a healthy one, and that fact — rated P1 by Review 4, agreed here — is recorded in the section of the ledger the termination rules do not point at. Fixing it needs a sentence of user-facing copy, which is exactly what the scope constraint forbade this run, so it is the right first item for whoever owns the next one.

All findings above go to **NEXT ROUND** except finding 4, which is recorded as a regression from this run's own pass 4.
