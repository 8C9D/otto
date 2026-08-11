# REVIEW-4 - pass 4 (failure behavior: F3, F4, F5, R0-1), commit range `c49ece2..d3eb18a`

**VERDICT: PASS-WITH-FINDINGS**

Two commits, eleven files, no schema change, no prohibited action, nothing worse than `BASELINE.md`.
Three of the four fixes are real, correctly scoped, and guarded by tests that fail for the right reason when the fix is broken - I broke each one the way the commit message says it was broken and reproduced the quoted failure verbatim.

The fourth, **R0-1, has no executable guard at all**, and the falsification on record does not touch the line the fix consists of.
I proved that by reverting `TodayView.swift:115` to its pre-fix expression and watching all 173 tests stay green.
That is the contract's named hazard - a test that passes before and after the change - inside the pass whose own rules say every added test must be falsified.
It is a P1 verification finding rather than a rejection because the code itself is right by inspection, the app target compiles it, and no delivery behavior changes.

The stage is not rejected.
Unlike pass 2, nothing here moves the app from delivering reminders to not delivering them: `canClaimCoverage` feeds exactly one call site, the Today section plan, and nothing that reaches `UNUserNotificationCenter`.

---

## 1. Verification re-run here, not read from `BASELINE.md`

| measurement | `BASELINE.md` claims | re-derived at `d3eb18a` | result |
|---|---|---|---|
| `scripts/verify.sh` | 526 host tests (OttoDomain 246 / OttoPersistence 112 / OttoUI 168), lint clean under `--strict` | **exit 0**; OttoDomain 246, OttoPersistence **113**, OttoUI **173**, **total 532**; `xcodegen generate` ok; app target builds; `swiftlint --strict` clean | ✅ +6, nothing worse |
| simulator suite (`xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"`, run from `Packages/OttoUI/` per REVIEW-2's note) | 19 tests, 7 known issues, `** TEST SUCCEEDED **` | `✘ Test run with 19 tests in 3 suites passed after 2.822 seconds with 7 known issues`, `** TEST SUCCEEDED **`, exit 0 | ✅ identical |
| parent `c49ece2` OttoUI count | - | fresh clone, `checkout c49ece2`, `swift test`: `✔ Test run with 169 tests in 29 suites passed` | ✅ so this range is exactly **+4 tests, +1 suite** |

Commit-message claim "*173 OttoUI tests (168 at baseline, +1 from the previous pass), 113 persistence, 246 domain, lint clean*" - **reproduced exactly at `d3eb18a`.**
The same claim at `c7bfe46` was **false**, which `d3eb18a` says itself.
I confirmed it rather than taking the confession: a clean clone at `c7bfe46` gives `Done linting! Found 3 violations, 3 serious in 201 files`, and they are exactly the three named -

```
CoverageHonestyTests.swift:21:9: error: Nesting Violation: Types should be nested at most 1 level deep (nesting)
NotificationScheduler.swift:404:1: error: File Length Violation: File should contain 400 lines or less: currently contains 404 (file_length)
NotificationScheduler.swift:11:8: error: Type Body Length Violation: Actor body should span 250 lines or less excluding comments and whitespace: currently spans 253 lines (type_body_length)
```

The rule "never end a pass with the linter worse than `BASELINE.md`" was broken at `c7bfe46` and repaired inside the same stage at `d3eb18a`, which is the correct handling.
`.swiftlint.yml` is untouched by the range, so "no limit is weakened" holds.
The word "pushed" in `d3eb18a`'s message is loose: `git ls-remote origin` still shows `refs/heads/main` at `406a5a6` and no remote branch contains `d3eb18a`, so nothing left this machine.

## 2. Every falsification claim re-performed

Each break was applied alone, run, then reverted with `git checkout -- .`; `git status --porcelain` was empty before and after every one, and is empty now at `d3eb18a`.

**F4** - `isTimeSensitive: kind.isTimeSensitive` → `false` (`NotificationActionHandler.swift:167`):

```
✘ "a snoozed deadline warning keeps its time-sensitive level; a snoozed ordinary rung does not gain one"
   NotificationActionTests.swift:137:9: (deadlineSnooze → …isTimeSensitive: false…).isTimeSensitive → false
✘ Test run with 9 tests in 2 suites failed after 0.014 seconds with 1 issue.
```

Reproduced verbatim.
**I then pinned the other direction**, which the message does not claim: hard-coding `true` fails the *lead* half at `NotificationActionTests.swift:160:9`.
So the test cannot be satisfied by any constant, which is the right answer to this repository's documented hazard at this seam.

**F5** - the loop reverted to a bare `try await client.add(spec)` (`NotificationScheduler.swift:187`):

```
✘ "a refused add does not abandon the rungs behind it - every desired rung is attempted"
   NotificationReconciliationTests.swift:136:9: (attempted.count → 1) == (desiredCount → 5)
   NotificationReconciliationTests.swift:137:9: (Set(attempted.map(\.identifier)).count → 1) == (desiredCount → 5)
✘ Test run with 11 tests in 1 suite failed after 0.021 seconds with 2 issues.
```

Reproduced verbatim, including the "attempted.count 1 against a desired set of 5" figures `d3eb18a` quotes.
The supporting claim that the order is deterministic is true and I checked it at the source: `SlotBudget.swift:23-33` sorts on `(day, priority, kind, subscriptionID.uuidString)`, a total order, so "the same rungs lost their slot on every pass" is a fact and not a supposition.

**F3** - `apply(nil)` deleted from the catch (`NotificationStatusStore.swift:51`):

```
✘ "a failed pass drops the previous outcome - no claim beats a stale one"
   CoverageHonestyTests.swift:63:9: (store.outcome → ScheduleOutcome(… coveredThrough: 2026-11-04 …)) == nil
✘ Test run with 2 tests in 1 suite failed after 0.045 seconds with 1 issue.
```

Reproduced verbatim, `coveredThrough 2026-11-04` included.
This falsifies the **store** half of F3 only; see finding 2 for the other half.

**R0-1** - `canClaimCoverage` forced to `true` (`ScheduleOutcome.swift:32`):

```
✘ "a pass that failed some subscriptions' ledgers may not claim coverage"
   CoverageHonestyTests.swift:75:9: (…ledgerFailures: [18B8B0E5-…]).canClaimCoverage → true
✘ Test run with 173 tests in 30 suites failed after 0.086 seconds with 1 issue.
```

Reproduced - and it is the wrong break, which is finding 1.

---

## Findings

### 1. P1 - R0-1's fix is the one line no test can see, and the recorded falsification breaks something else

**severity:** P1.
Not because the committed code is wrong - it reads correctly, the app target builds it, and nothing about delivery changes - but because R0-1 is reported closed on evidence that would be identical had the fix never been written, in a run whose binding rule is *"Every test added must be falsified: break the fix, watch the test fail with the right failure"* and in a repository the contract says has shipped several tests that pass for the wrong reason.

**evidence.**
R0-1's fix is one expression, `TodayView.swift:115`:

```swift
canClaimCoverage: model.notifications?.outcome?.canClaimCoverage ?? false
```

I reverted exactly that to the pre-fix `canClaimCoverage: model.notifications?.outcome != nil` and ran the whole package:

```
✔ Test run with 173 tests in 30 suites passed after 0.053 seconds.
```

Nothing detects it.
The two tests that mention `canClaimCoverage` cannot:

- `CoverageHonestyTests.swift:69-76` asserts `ScheduleOutcome.canClaimCoverage` against `ledgerFailures`, which is the declaration `ledgerFailures.isEmpty` restated through its own alias (`ScheduleOutcome.swift:32`). It is a property test of a one-line computed property, not a test of the screen the finding is about.
- `TodaySectionPlanTests.swift:80-89` is a **pure rename**. Every one of its six expectations existed at `c49ece2` under `hasScheduleOutcome` and asserted the same thing; `TodaySection.plan` itself is behaviourally unchanged by this diff, since only the label on the boolean moved. The suite went 169 → 173 without gaining a single assertion that binds `ledgerFailures` to what Today renders.

The break the commit message records - "*Falsified: the claim survives with a non-empty `ledgerFailures`*" - forces `canClaimCoverage` to `true`, which I reproduced: it fails exactly one test out of 173, and it is a test of the property, not of the fix.
So the sentence reads as if the fix were exercised and it was not.
This is the contract's "evidence citations that don't say what they're claimed to say", one layer down from where REVIEW-2 found the same shape (its finding 3, rated P2 there because the commit message **disclosed** the limitation; here it does not, which is why this is a band higher).

**why the builder missed it.**
`TodaySection.Input` was extracted from the view builder for precisely this reason, and the file says so at `TodayView.swift:6-9`: *"Wave 9A defect 1 lived exactly there … a decision no store-level test could see."*
The fix was then made on the one line that is still **inside** the view builder - the mapping from `outcome` to the input - and the falsification was aimed at the testable end of the pair instead.
Renaming the field made `TodaySectionPlanTests` *look* like the guard, because its diff is in the same commit and mentions the same word.

**what would close it (stated, not applied).**
Lift the mapping out of the body the same way `Input` was lifted - a `static func input(…)` or an equivalent seam - and assert that an outcome carrying a `ledgerFailures` entry produces `canClaimCoverage: false`.
Test-only plus one extraction, no new capability, no schema change.

### 2. P2 - F3 is fixed in two places, only one is tested, and the untested one is the path that runs while nobody is watching

**severity:** P2.
The change is three lines and reads correctly; `NotificationCoordinator` being untested is already on record (`docs/next-wave.md`: *"Carry-over candidates … simulator-hosted `NotificationCoordinator` tests"*).
It is a finding because the commit message states F3 as closed without saying that half of it has no evidence.

**evidence.**
`NotificationCoordinator.swift:1` opens `#if os(iOS)` and `:255` closes it, so host `swift test` never compiles the file.
I reverted `rescheduleSoon` (`:114-126`) to the pre-fix shape:

```swift
if let outcome = try? await scheduler.reschedule(…) { onOutcome?(outcome) }
```

```
✔ Test run with 173 tests in 30 suites passed after 0.053 seconds.
```

That path carries `.foreground` (`:110`), `.notificationDelivered` (`:226`), `.notificationAction` (`:251`), `.timeZoneChange` (`:96`) and `.significantTimeChange` (`:101`) - every trigger that fires without the user driving a store mutation, which is the entire population of passes on a phone in a drawer.
Only `.stateChange` reaches `NotificationStatusStore.reschedule()`, and that is the one the new test covers.
The change is compile-checked by `verify.sh`'s app-target build (`OttoApp.swift:87-89` passes the now-optional closure straight into `apply`), so it is not unverified in the compile sense - it is unverified in the behavioural sense.

Related, and worth recording next to it: `handleBackgroundRefresh` (`:149-184`) still never calls `onOutcome` on **either** path, so a `BGAppRefreshTask` pass neither publishes a fresh outcome nor clears a stale one.
That is pre-existing and outside F3's cited lines (`PROD-READINESS.md:64` cites `:113-119`), and the exposure is small because `appDidBecomeActive` runs a fresh pass, but "a failure now clears it" is stated more broadly in the commit message than the diff delivers.

**why the builder missed it.**
The seam boundary was read correctly - `OttoStoresTests` can reach `NotificationStatusStore` and nothing can reach an `#if os(iOS)` `@MainActor` class that owns a `BGTaskScheduler` registration - and the falsification was then performed at the reachable end and reported for the finding as a whole.

### 3. P2 - the new test's second assertion cannot fail, and its comment says it can

**severity:** P2, and it is this repository's signature defect appearing inside the test written to fix an honesty finding.

**evidence.**
`CoverageHonestyTests.swift:64-66`:

```swift
// The permission is still refreshed - a failed pass says nothing about
// whether notifications are allowed.
#expect(store.permission == .authorized)
```

I deleted `permission = await client.permission()` from the catch at `NotificationStatusStore.swift:52` and ran the suite:

```
✔ Test run with 2 tests in 1 suite passed after 0.002 seconds.
```

It passes because `store.apply(outcome(coveredThrough: day))` at `:57` already set `permission` to `.authorized` through `apply`'s `if let` branch, and `FixedClient.permission` returns the same value.
The assertion holds whether the refresh happens, does not happen, or is replaced by nothing at all.
This is the same shape as the contract's own example - `body.contains("$15.99")` passing in two locales because `CA$15.99` contains it - a green assertion whose expected value was already true for an unrelated reason.

**why the builder missed it.**
The test was written to describe the *comment* in the production code (`NotificationStatusStore.swift:49-50`, "The permission is still worth refreshing"), and a sentence in a comment was turned into an `#expect` without asking what state the assertion would have to distinguish.
Seeding the store's permission to something other than the client's answer - the only arrangement under which the line means anything - would have shown it immediately.

### 4. P2 - the ledger records none of this pass, so two deliberate deferrals exist only in a commit message

**severity:** P2, bookkeeping.
Nothing is marked resolved without an artifact; this is the inverse error, artifacts without the mark, and it is the same one REVIEW-3 raised as its finding 4 - one pass after the convention was established.

**evidence.**
`git diff c49ece2..d3eb18a --stat -- PROD-READINESS.md` is empty.
`PROD-READINESS.md:149-152` still has blank **terminal state** cells for F4, R0-1, F3 and F5, while `:154` carries `**RESOLVED** - b15b0a6, remediated after Review 3` for F6, written by `c49ece2`.
So the document's own convention is per-pass, and this pass did not follow it.

Two consequences beyond tidiness:

- `c7bfe46`'s closing paragraph - *"Withdrawing the sentence trades a false statement for no statement; saying something useful in its place would be new copy, so it is NEXT ROUND"* - appears in **no** NEXT ROUND section. `PROD-READINESS.md:172-179` is where the next round is read from, and this item is not there. A deferral that lives only in a commit message is not deferred, it is dropped, and this one is the residual described in finding 5.
- This stage's brief names six failure-behavior questions (permission revoked, no background wake, 64-slot budget exhausted, storage exhaustion, killed mid-write, clock jump). The pass answered the four frozen findings, which is correct under the freeze rule, but the freeze rule's other half is that post-freeze discoveries are *appended to NEXT ROUND*. Nothing was appended, including the two the diff walks straight past: `ScheduleOutcome.truncatedAfter` (`ScheduleOutcome.swift:13`) has **no consumer anywhere** outside its own construction, so budget truncation reaches the user only as a quietly shorter date; and `ledgerFailures` is logged as a bare **count** (`OttoLog.swift:87`), so after R0-1's fix the coverage sentence disappears and no artifact on the device says which subscription caused it.

**why the builder missed it.**
The pass's own rules are written per-commit ("state what you're changing", "record the artifact output", "record what you saw in the commit message"), and all of that was done well.
The ledger update is the one step that is not per-commit and has no line in the per-pass rules, so it fell between the passes that do have one.

### 5. P1 (NEXT ROUND, not this stage's work) - the withdrawn sentence takes the true half with it, and leaves an authorized user with no notification surface at all

**severity:** P1 for the state of the product.
**Not** a regression this stage must fix: the ledger's fix column for R0-1 (`PROD-READINESS.md:68`) says exactly *"Gate the coverage claim on an empty `ledgerFailures`, reusing the existing footer"*, and F3's (`:64`) says *"Clear or invalidate `outcome` when a pass fails"*.
The builder implemented what Review 0 froze, predicted this consequence, and deferred it for the right reason - a replacement sentence is new user-visible copy, which the scope constraint forbids.
I record the mechanism because finding 4 means it is currently written down nowhere.

**evidence.**
`TodaySection.plan` (`TodayView.swift:41-68`) emits `.notificationStatus` only when `permission != .authorized` (`:43`) and `.coverage` only when `canClaimCoverage` **and** the permission can deliver (`:63-64`).
For an **authorized** user, those are the only two notification surfaces Today has.
So after this pass:

| situation | Today before `c7bfe46` | Today after |
|---|---|---|
| every pass throws (repository read fails, `add` refused) | "Reminders scheduled through Nov 4" - false, but a date that visibly stops advancing | **nothing** |
| pass succeeds, 1 of 3 subscriptions' ledger failed | "Reminders scheduled through Nov 4" - true for two, false for one | **nothing, for all three** |

The second row is the one that matters and it is the common case: R0-1 is an *all-or-nothing* gate, so one subscription's failure withdraws a statement that was accurate for the others, and `ledgerFailures` being logged as a count (`OttoLog.swift:87`) means neither the user nor an investigator can tell which one.
A screen that renders identically whether the engine is healthy or has failed on every pass since install is this project's own stated characteristic failure, and `NotificationStatusStore.swift:7-9` names that screen as the thing that must never fail silently.

"No claim beats a false one" is defensible and I am not arguing the fix should be reverted - a false coverage promise is worse.
The point is that the pass closed a P1 by deleting a sentence and the resulting state is still P1, so the finding is not disposed of, it is moved.

**why the builder missed it.**
It did not miss it - `c7bfe46`'s last paragraph states it plainly.
It missed putting it in the file that outlives the commit message.

---

## Checked and found clean (recorded so severity is not inflated by omission)

- **No SwiftData schema change.** `git diff --name-only c49ece2..d3eb18a` touches no file under `Packages/OttoPersistence/`, no model, no `OttoMigrationPlan`, no `OttoContainerFactory`. `ScheduleOutcome` appears nowhere in `OttoPersistence` or `OttoDomain` (grep returns zero hits), so `canClaimCoverage` is a computed property on a plain in-memory `Sendable` struct and not a schema property in the sense the constraint freezes. V3 is untouched.
- **No prohibited action.** `406a5a6` is an ancestor of `d3eb18a` (no rewrite); `git reflog` shows two ordinary commits and no rebase, amend or reset; `git ls-remote origin` still has `main` at `406a5a6` and no remote branch contains HEAD (not pushed); no `.github/workflows/`, `Package.swift`, `project.yml`, `docs/`, `DECISIONS.md` or `README.md` change; no device contact, no network call, nothing in `<backup-dir>` touched. My own falsifications were in-tree edits reverted with `git checkout -- .`, and every scratch clone lives outside the repository.
- **No feature smuggled in.** No screen, toggle, export field, model, config key, or line of new copy. The only user-visible change is that an existing footer is withheld in two more cases, which is a subtraction.
- **The public-signature change has exactly the call sites claimed, and all of them were updated.** `onOutcome` is declared at `NotificationCoordinator.swift:38`, invoked at `:124`, and assigned in exactly one place, `Otto/App/OttoApp.swift:87` - grep over `Otto/` and `Packages/` returns no other assignment and no test double, because `NotificationCoordinator` has no tests. `NotificationStatusStore.apply` is called at `OttoApp.swift:88`, `NotificationStatusStore.swift:42,51`, and `CoverageHonestyTests.swift:57`, and nowhere else. `TodaySection.Input.canClaimCoverage` is constructed at `TodayView.swift:108` and `TodaySectionPlanTests.swift:22` only. `Previews.swift` builds every preview through an `AppModel` with `notifications` defaulted to nil (`AppModel.swift:67`), so no preview constructs either type and none needed changing. The app target compiles all of it - `verify.sh`'s `xcodebuild` step passed at HEAD.
- **F4 is not inert on hardware.** The fix only matters if the app may actually raise a notification's interruption level, and it may: `project.yml:85` declares `com.apple.developer.usernotifications.time-sensitive: true`, and `LiveNotificationClient.swift:210-211` maps `isTimeSensitive` onto `content.interruptionLevel = .timeSensitive`, with `:194` reading it back symmetrically. Focus behaviour itself remains **UNVERIFIED** - the device is prohibited - and the commit message says exactly that rather than more.
- **F4 has no blast radius on the reconcile diff.** `reconcile` compares whole specs (`NotificationScheduler.swift:186`), so changing `isTimeSensitive` could in principle force mass re-adds - except snoozes are filtered out of `planned` at `:171` and the planned rungs already derived the flag from the kind at `:355` and `:368`. Only the snooze path changes, and snoozes never enter the diff.
- **The unparseable-identifier fallback did not change severity by accident.** `snoozedKind` falls back to `.trialDaily` (`NotificationActionHandler.swift:198`), and `PlannedReminder.Kind.isTimeSensitive` returns `false` for `.trialDaily` (`PlannedReminder.swift:46-47`), so a snooze built from an identifier Otto cannot parse still gets the quiet level. The fix promotes only the three kinds the spec promotes.
- **F5 does not relocate the bug or hide an error.** The throw is preserved (`NotificationScheduler.swift:203`), it is raised after the log line so the `added`/`failed` split is on record, and the rethrow reaches `OttoLog`'s wrapper (`OttoLog.swift:90-95`) which logs `pass threw trigger=… error=<type>` and rethrows rather than swallowing. The device ends every pass holding a superset of what the old code left it holding.
- **F3 does not leave permission stale in a way that matters.** `apply(nil)` deliberately does not touch `permission` (`NotificationStatusStore.swift:63-68`); the store's own catch refreshes it from the system immediately after, and a denied permission never reaches this path at all because `NotificationScheduler.reschedule` *returns* rather than throws when it cannot deliver (`:78-91`). `TodayView`'s `.task` also calls `refreshPermission()`.
- **Nothing else reads the outcome.** `NotificationStatusStore.outcome` has exactly two consumers, `TodayView.swift:115` and `:189`, and the second is inside the section the first gates, so the plan and the render cannot disagree.
- **No fabricated or unreproducible claim.** Every factual assertion in both commit messages was checked against the tree or re-measured: the hard-coded `false`, the aborting loop, the stale outcome, the deterministic ordering, the three lint violations, the four falsifications, the test counts at HEAD and at the parent. All hold. The two overreaches are R0-1's falsification (finding 1) and "the coordinator reports failure as nil" being stated without saying it is unguarded (finding 2).
- **Severity of the frozen findings is not deflated.** F3, F4 and F5 were P1 and are closed with tests that fail correctly; R0-1 was P1 and its code is closed with no test, which is finding 1 rather than a quiet downgrade.

## What this verdict means for the next stage

PASS-WITH-FINDINGS.
Pass 5 (F2, observability) may proceed on this tree.

Carry forward, in order:

1. **Finding 1** is the only one that touches a frozen finding's closure. Either give R0-1 a guard that fails when `TodayView.swift:115` is reverted, or say in the ledger that R0-1 has no executable regression guard - the same choice REVIEW-2 offered for F1 and the same wording would do.
2. **Finding 4** is a five-minute edit that pass 5 will have to make anyway, and it is what keeps finding 5 from vanishing. Fill the four terminal-state cells and append the withdrawn-sentence residual, `truncatedAfter`'s absent consumer, and `ledgerFailures` being logged as a count to NEXT ROUND.
3. **Finding 3** is one line in a test and should be fixed while `CoverageHonestyTests` is still warm: seed the store's permission and the client's answer to different values so the assertion has something to distinguish.
4. **Findings 2 and 5** are NEXT ROUND by construction - one needs a simulator host for `NotificationCoordinator` that the project already lists as a carry-over, the other needs copy the scope constraint forbids this run.
