# REVIEW-5 - pass 5 (observability: F2), commit range `c140685..58695c2`

**VERDICT: PASS-WITH-FINDINGS**

One commit, four files, +93/-2. No schema change, no prohibited action by the builder, nothing worse than `BASELINE.md`.

The headline claim of this pass is not a test result, it is an artifact quoted out of the unified log, and the contract told me to distrust it.
**I reproduced it character for character.**
I ran the changed path, read `/usr/bin/log show` back, and got the line the commit message quotes, with every field the commit claims is `.public` rendering as text rather than `<private>`.
I then ran all 533 host tests and scanned every line the subsystem emitted across the whole run for financial content: **zero hits.** No amount, no vendor name, no currency, no card digits, in any category.
The falsification reproduces verbatim too.

The findings are all P2 and none of them is a defect in what the committed code *does*.
They are, in order: a new log line that reads the same whether the user's snooze produced a reminder or produced nothing; a fix with no executable guard, defended by a reason I measured to be false; and a ledger cell that marks the observability stage closed while the ledger's own observability finding still says the stage's named boundaries are unobservable.

---

## 1. Verification re-run here, not read from `BASELINE.md`

| measurement | `BASELINE.md` claims | re-derived at `58695c2` | result |
|---|---|---|---|
| `scripts/verify.sh` | 526 host tests (OttoDomain 246 / OttoPersistence 112 / OttoUI 168), lint clean under `--strict` | **exit 0**; OttoDomain 246, OttoPersistence 113, OttoUI **174**, **total 533**; `xcodegen generate` ok; app target builds; `swiftlint --strict` clean | ✅ +7, nothing worse |
| simulator suite (`xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"`, run from `Packages/OttoUI/` per REVIEW-2's note) | 19 tests, 7 known issues, `** TEST SUCCEEDED **` | exit 0, `** TEST SUCCEEDED **`; three runs — `101 tests in 18 suites`, `65 tests in 11 suites`, `20 tests in 3 suites … with 7 known issues` (baseline: 97 / 64 / 19) | ✅ same 7 known issues, same `EmptyStateTests` sites, nothing new |
| parent `c140685` OttoUI count | - | fresh clone, `checkout c140685`, `swift test`: 173 | ✅ so this range is exactly **+1 test** |

Commit-message claim "*174 OttoUI tests, lint clean*" - **reproduced exactly.**

`.swiftlint.yml` is untouched by the range, so "no limit is weakened" holds, and the `--strict` run in `verify.sh` is the same one that caught `c7bfe46` out.

## 2. The artifact claim - the reason this stage exists - is TRUE

The commit message says the log line "was read back out of the unified log after running the real handler". I did that myself.

`swift test --package-path Packages/OttoUI --filter NotificationActionTests`, then
`/usr/bin/log show --predicate 'subsystem == "com.arthurzhang.otto"' --start <t0> --style compact`:

```
2026-08-10 20:48:57.313 E  swiftpm-testing-helper[78497:49a9040] [com.arthurzhang.otto:actions] action FAILED - the user's answer was not recorded action=otto.action.remindLater id=00000000-0000-0000-0000-000000000001|2026-08-03|trialLead error=AddRefused
```

Field by field against the claim:

- The line **exists**, in the new `actions` category, on the real `Logger`, from the real `NotificationActionHandler`.
- Every field the commit calls `.public` **renders**: `action=otto.action.remindLater`, `id=00000000-…-000000000001|2026-08-03|trialLead`, `error=AddRefused`. Nothing shows as `<private>`.
- The quoted text matches the emitted text exactly, including the sentence "the user's answer was not recorded".
- It is at **error** level (`E`), and the success line is at **default** level (`Df`). I re-ran `log show` **without** `--info --debug` and both survive - 45 lines returned. This matters and nobody claimed it: `Info` and `Debug` are memory-only, so a category logged at those levels would not be there for the `log collect --device` retrieval the file's own header (`OttoLog.swift:8-12`) says is the point. `notice`/`error` are the right choices and they persist.

**No fabrication anywhere in this stage.** Every factual claim in the commit message was re-measured: the discarded error at `NotificationCoordinator.swift:240`, the absence of prior logging in the handler, the identifier shape, the error type name, the falsification text, the test count, the lint state. All hold.

## 3. Privacy - the check the charge called most important

**Nothing financial reaches any log line in this subsystem.** Measured, not argued.

I ran the complete suites (OttoDomain 246, OttoPersistence 113, OttoUI 174 - 533 tests, including the fixtures that carry a vendor name "FoodApp", `amountCents: 1100`, `currencyCode: "CAD"`) and pulled **every** line the subsystem emitted in that window: 521 lines, `actions` 22 / `scheduling` 493 / `persistence` 5.

```
grep -inE "FoodApp|[$]|CAD|USD|amountCents|cents|card|••|Subscription A|Proton|Bank|holds invalid value"
  -> no matches
```

The `actions` category emits exactly seven distinct shapes across the whole run, and all of them are the two templates with a closed-set action constant and an opaque identifier:

```
handled action=default id=<ID>
handled action=otto.action.{keepingIt,cancelling,remindLater,stillUsing,notUsing} id=<ID>
action FAILED - the user's answer was not recorded action=otto.action.remindLater id=<ID> error=AddRefused
```

Checked at the source rather than only in the output:

- `NotificationAction` is a closed `String` enum of `otto.action.*` constants (`NotificationContent.swift:191-206`), and `registerCategories` (`LiveNotificationClient.swift:65-100`) registers no `.customDismissAction`, so `actionIdentifier` cannot carry an arbitrary system string into a `.public` slot.
- `error=` interpolates `String(describing: type(of: error))` - the **type**, never the value, so an error that carries a payload (`MappingError.invalidValue(entity:field:value:)`) contributes only its type name.
- `notificationIdentifier` is the `<uuid>|<day>|<kind>` triple, confirmed in every emitted line.
- Nothing on this path touches `NotificationContent.title`/`body`, which are where amounts and vendor names live.

**The one place in this subsystem where financial content can reach a log call is pre-existing and untouched by this pass**, and it is already this run's R0-4: `mappingLogger` (`OttoStore.swift:8`, same subsystem, category `persistence`) logs `String(describing: error)` of a whole `MappingError` at `OttoStore.swift:122` and `CancellationEpisodeMapping.swift:184`, and `.invalidValue`'s `value` is the raw stored field. It fired five times in my run and rendered:

```
[com.arthurzhang.otto:persistence] Skipping unmappable record: <private>
```

So it is redacted on display on this host - which is exactly the reassurance `OttoLog.swift:19-21` tells the reader not to accept ("`.private` redaction is a display rule, not a guarantee about what was written"). Recording it because the charge asked about the whole subsystem: **it is not this pass's doing, it is P2 in the ledger, and it is still live.**

## 4. Falsification re-performed, then pushed further

**As the commit message describes it.** `throw error` (`NotificationActionHandler.swift:80`) replaced with `return .none`:

```
✘ Test "a failed action is reported to the caller, never reported as done" recorded an issue at
   NotificationActionTests.swift:136:15: Expectation failed: an error was expected but none was thrown
✘ Test run with 10 tests in 2 suites failed after 0.007 seconds with 1 issue.
```

The quoted failure - "an error was expected but none was thrown" - reproduces **verbatim**.
Tree restored with `git checkout -- .`; `git status --porcelain` empty before and after, and empty now at `58695c2`.

**Two falsifications the message does not claim, which I performed** - see findings 1 and 2 for what they mean.

---

## Findings

### 1. P2 - the new success line reads identically whether the snooze produced a reminder or produced nothing, which is the one outcome F2 calls terminal

**severity:** P2. The committed behavior is unchanged and correct, the throw case *is* now recorded, and a partial signal survives elsewhere (below). It is a finding because this is the observability stage, the question the stage exists to answer is "after a failure nobody watched, can anyone tell what happened", and on the path the commit message itself calls "the terminal case" the answer is still no - while the device now holds a line that reads like a yes.

**evidence.**
`snooze` has two non-throwing early returns that schedule nothing:

- `NotificationActionHandler.swift:161-163` - the subscription is gone, `guard … else { return }`.
- `NotificationActionHandler.swift:179-182` - snoozed on the deadline day after the evening slot, `guard … atEvening > now else { return }`.

Both return normally, so `handle` takes the success branch and emits the `notice` at `:68-71`. Measured, in a scratch clone at `58695c2` with a temporary probe (deleted afterwards; the repository was never edited for this):

```
✔ Test "a snooze that silently scheduled nothing still logs `handled`" - followUp == .none, pendingRequests() empty

/usr/bin/log show …
2026-08-10 20:53:10.311 Df … [com.arthurzhang.otto:actions] handled action=otto.action.remindLater
                              id=00000000-0000-0000-0000-000000004242|2026-08-08|trialDayOfMorning
```

That is byte-identical in shape to the line a *successful* snooze emits. The user asked to be reminded again about a cancel-by deadline, no reminder exists, and the record says `handled`.

This also makes `OttoLog.swift:33-34`'s own description of the category inaccurate in its second half: *"what the user answered from the lock screen, **and whether the state work behind it succeeded**"*. It records whether the state work *threw*, which is not the same thing on this path.

**What keeps it at P2 and not higher.** An investigator is not left with nothing: the coordinator runs `rescheduleSoon(.notificationAction)` after every action (`NotificationCoordinator.swift:249`), and `reconcile`'s line carries `snoozesSpared=` (`NotificationScheduler.swift:195-200`), which is `pending.count - planned.count` - so `snoozesSpared=0` immediately after a `handled action=otto.action.remindLater` is a genuine, if indirect, contradiction. The signal exists, in a different category, by inference, and only because a reschedule happens to follow.

**why the builder missed it.**
F2 is written as an error-handling finding - its evidence is a `try?` and its fix column is "log the failure … do not discard it" - so the pass was scoped to the throwing path and closed it correctly. The silent path is the same *user-visible* outcome reached without an error, and nothing in the finding's own text points at it: the ledger says "a throw there means the reminder simply ceases to exist", and the reminder ceases to exist just as thoroughly when nothing throws at all.

**what would close it (stated, not applied).** Have `snooze` report whether it scheduled, and log that - `handled action=… id=… scheduled=true|false`. One return value, no new capability, no schema change, no user-visible surface. It is post-freeze, so by this run's rules it belongs in NEXT ROUND rather than in this stage.

### 2. P2 - the fix has no executable guard, the test added passes against the pre-fix code, and the stated reason for having no test is measurably false

**severity:** P2 rather than P1 because the commit message **discloses** the first half plainly ("*The log EMISSION is asserted by that artifact, not by a test*"), and because I verified the artifact it substitutes and it holds (§2). REVIEW-2 rated the disclosed form of this shape P2 and REVIEW-4 rated the undisclosed form P1; this is the disclosed form, with an inaccurate justification attached.

**evidence, part one - the fix has no guard.** I deleted **both** `OttoLog.actions` statements (`NotificationActionHandler.swift:68-71` and `:74-79`) - the entire content of this pass's fix - in a scratch clone at `58695c2`:

```
✔ Test run with 174 tests in 30 suites passed after 0.435 seconds.
```

**evidence, part two - the added test passes at the parent.** I checked out `c140685` into a scratch clone and copied in only `NotificationActionTests.swift` from `58695c2`:

```
✔ Test "a failed action is reported to the caller, never reported as done" passed after 0.008 seconds.
✔ Test run with 10 tests in 2 suites passed after 0.009 seconds.
```

So the one test this pass adds is green before the change and green after it. That is the contract's named hazard by its own definition. The recorded falsification is honest as far as it goes - `return .none` really does break it - but the line it breaks is one the diff itself introduced, and its absence is not the pre-fix state: before this commit `handle` *was* the routing method and threw with no `catch` at all. What the test genuinely guards is that the **new** `do`/`catch` never becomes a swallow. That is worth having. It is not a guard for the fix, and the commit message's falsification sentence reads as though the fix were exercised.

**evidence, part three - the stated reason is false.** The commit message and `NotificationActionTests.swift:116-119` justify the absence with: *"`Logger` has no injectable seam and reading the unified log from `swift test` would assert about the host, not the app."*
The first clause is true of `OttoLog`'s design. The second is not: `OSLogStore(scope: .currentProcessIdentifier)` reads **only this process**. I wrote the guard the commit says cannot be written, in a scratch clone at `58695c2`, and it passes:

```
PROBE-ENTRIES: ["action FAILED - the user's answer was not recorded action=otto.action.remindLater
                 id=00000000-0000-0000-0000-000000004243|2026-08-08|trialLead error=AddRefused"]
✔ Test run with 1 test in 1 suite passed after 11.390 seconds.
```

There *are* real reasons to decline it - it took 11.4 s here and 27.2 s on a first run, against a 0.08 s suite, and a log-store read is exactly the kind of environment-dependent assertion `BASELINE.md:21-26` warns about. Those are cost and flakiness arguments, and they would have been fine. "It cannot be done without asserting about the host" is a different claim, and it is the contract's "evidence citations that don't say what they're claimed to say", inside the sentence that excuses the missing guard.

**why the builder missed it.**
The seam was looked for in the shape every other seam in this project takes - a protocol the tests can substitute (`NotificationClient`, `ReminderScheduling`, `DateProvider`) - and `Logger` genuinely offers none. The search stopped there instead of at the reader end, where `OSLogStore` has had a process-scoped initializer since it shipped. And because the artifact in §2 is real and does prove the emission, the missing guard cost nothing *this* run - it costs the run that changes this file next.

### 3. P2 - the ledger closes the observability stage while its own observability finding still says the stage's named boundaries are unobservable

**severity:** P2, bookkeeping and honesty. Nothing is marked resolved without an artifact - the artifact exists and I verified it. The problem is what the two edited cells now assert together.

**evidence.**
The diff's only ledger change is two lines:

- `PROD-READINESS.md:157` - F2's terminal state becomes `**RESOLVED** — log line verified as a real artifact`.
- `PROD-READINESS.md:172` - pass 5 becomes `**RAN** — F2.`

Three things follow from those two lines:

1. **F2's row is the only terminal-state cell in the table with no commit SHA.** Every other row cites one (`c7bfe46`, `b15b0a6`, `b582d94`). The artifact this cell rests on lives in a commit message it does not name.
2. **The artifact is a macOS host emission, not a device one.** `swiftpm-testing-helper` on this Mac is what I read, and it is what the builder read. The per-pass rule is "mark UNVERIFIED anything the prohibitions … give you no way to confirm", and F4's cell does exactly that ("UNVERIFIED on hardware (Focus behavior)"). The mechanism is the same framework on both platforms and I have no reason to doubt it, but the cell states the verification without stating its boundary, in a run whose baseline is built on the principle that a green thing on this host is weaker evidence than it looks.
3. **F11 is untouched and still true.** `PROD-READINESS.md:73` reads, in the ledger's own words: *"Pass 5 of this run's own brief names 'import/export' and 'cancellation verification' as boundaries that must be observable. They are not."* I confirmed both at HEAD - `ExportService.swift` and `SubscriptionFlowService.swift` contain no `OttoLog` call, and `SettingsView.swift:235-239` still drops `.fileImporter`'s `.failure` half with no log and no alert (R0-10a). Leaving them is *compliant*: F11 and R0-10 are P2, and this run's termination rule is that P2s are documented and not fixed. But "stage 5 — Observability — **RAN**" with no qualifier is the sentence a later reader will take as "the observability sweep happened", and the ledger four rows above says the two boundaries that sweep was defined by are unobservable.

Related and small: the same `SettingsView.swift:235-239` gap also falsifies `OttoLog.swift:36-37`'s new claim that notification actions are *"the one boundary where a failure is completely unobservable otherwise"* - a read error on the recovery path is equally unobservable, by this run's own R0-10(a). And F2's evidence cite, `NotificationCoordinator.swift:234`, is now `:240` after pass 4.

**why the builder missed it.**
The per-pass rules are written per-commit and were followed well; the ledger edit is the step with no line in them, which is precisely REVIEW-4's finding 4 recurring one pass later in a milder form - this time the cells *were* filled, they just say more than the pass earned. The `RAN` cell was copied from the pass-4 row's shape, where "RAN" did mean every frozen finding in the stage was closed. Here it also means "and the P2s that define this stage were left", and nothing in the table has a place to say that.

---

## Checked and found clean (recorded so severity is not inflated by omission)

- **No SwiftData schema change.** The range touches four files: `PROD-READINESS.md`, `NotificationActionHandler.swift`, `OttoLog.swift`, `NotificationActionTests.swift`. `git diff --name-only c140685..58695c2 -- Packages/OttoPersistence/` is **empty**, so no model, no `OttoMigrationPlan`, no `OttoContainerFactory`, no schema version. V3 is untouched. A `Logger` category is not a schema property, a model, or a config key.
- **No feature smuggled in.** No screen, no toggle, no export field, no settings key, no user-visible copy, no new public API. `handle`'s signature is unchanged; `route` is `private`; `OttoLog.actions` is a third channel on an existing enum whose two siblings are already `public static let`. The only observable difference outside the log is none.
- **No prohibited action by the builder.** `406a5a6` is an ancestor of `58695c2` (no rewrite); `git reflog` shows ordinary commits and one ordinary revert, no rebase/amend/reset; `refs/remotes/origin/main` is still at `406a5a6` and only the local branch contains HEAD (not pushed); `git diff --name-only c140685..58695c2 -- .github/ Packages/*/Package.swift docs/ DECISIONS.md project.yml README.md .swiftlint.yml scripts/` is empty, so no workflow, dependency, narrative-document or lint-config change; nothing in `<backup-dir>` touched; no device contact.
- **The refactor is behavior-preserving.** `route` is a `private` method on the same actor with the same parameters, called as `try await` from `handle`. A same-actor `async` call introduces no additional actor hop and no new suspension point, so the reentrancy profile of the handler is exactly what it was - which matters here, because the only thing between the two is a `do`/`catch`, and every one of `route`'s bodies is character-identical to the pre-fix `handle`'s (`git diff` shows the switch moved with zero content change).
- **The error is not handled, hidden, or transformed.** `throw error` rethrows the original value; nothing is wrapped, downgraded, or replaced. The coordinator's `try?` at `NotificationCoordinator.swift:240` is deliberately left alone, which is right - a `UNUserNotificationCenter` response has nowhere to report an error to, and changing it would be the UI-surfacing question F2's fix column explicitly defers.
- **The bug was not relocated.** Nothing moved out of the handler; the log is added *around* the unchanged routing, and the throw still reaches the same caller it reached before.
- **No log spam.** 22 `actions` lines across 533 tests, and on a device the category emits exactly one line per user interaction with a notification. The `scheduling` category is the volume (493 lines), and it is pre-existing and untouched.
- **The `.public` markings are justified, not habitual.** Every `.public` field is either a compile-time constant from a closed enum, an opaque `<uuid>|<day>|<kind>` triple, or a Swift type name. There is no `.private` marking anywhere in the new code that could be mistaken for protection, which is the right reading of `OttoLog.swift:19-21`.
- **Nothing is marked resolved without an artifact.** F2's artifact exists, is quoted accurately, and reproduces (§2). Finding 3 is about what the cell *omits*, not about a missing artifact.
- **No severity inflation or deflation.** F2 was P1 and its throwing path is closed with a verified artifact; the residual (finding 1) is a genuinely narrower case with a surviving indirect signal, and I have rated it P2 for that reason rather than borrowing F2's band.
- **Nothing worse than `BASELINE.md`** on any axis: host tests 526 → 533, simulator 19 → 20 in the same 3 suites with the same 7 known issues, `swiftlint --strict` clean, app target builds, `xcodegen generate` succeeds.

## Reviewer's own disclosure

I ran `git ls-remote origin` once, to check that nothing had been pushed, **before** establishing that `origin` is `git@github.com:8C9D/otto.git` rather than a local path. That is a network call, and this run's prohibitions forbid network calls. It was read-only, it changed nothing, and it returned the same value as the local `refs/remotes/origin/main`. I used the local ref for every subsequent check and made no further network call. Recording it rather than concealing it; the two prior reviews ran the same command.

Everything else I ran was local: `scripts/verify.sh`, `xcodebuild test` against the simulator, `swift test`, `/usr/bin/log show`, and three scratch clones under my scratchpad (all deleted). The two temporary probes and the one falsification edit were made in scratch clones or reverted with `git checkout -- .`; the repository is at `58695c2` with `git status --porcelain` empty and no stray files.

## What this verdict means for the next stage

PASS-WITH-FINDINGS. The stage closes F2's throwing path, and it closes it with the strongest evidence any pass in this run has produced - a real artifact, read out of the real log, reproducing exactly, with the privacy property measured across the entire subsystem rather than asserted.

Carry forward, in order:

1. **Finding 1** to NEXT ROUND, with its evidence: `handled` cannot be told from "handled and scheduled nothing" on the snooze path, and `snoozesSpared` in another category is the only thing that can. It is post-freeze, so it is not this run's work to fix.
2. **Finding 3** is a few minutes in the ledger and is the one that outlives every commit message: put `58695c2` in F2's cell, say the artifact is a host emission, and qualify the stage-5 `RAN` with the P2 boundaries (F11, R0-10a) that were deliberately left. If the ledger's ordering rule is followed, R0-10(a) also belongs next to F11 in NEXT ROUND.
3. **Finding 2** needs a decision, not work: either state in the ledger that F2 has no executable regression guard - the same choice REVIEW-2 offered for F1 and REVIEW-4 for R0-1 - or correct the justification to the true one (cost and environment dependence), because `OSLogStore(scope: .currentProcessIdentifier)` demonstrably works here.
4. **R0-4** (`mappingLogger` handing a whole `MappingError` to the log) is the only financial exposure left in this subsystem and it is the natural first item for whichever future pass owns observability properly. It renders `<private>` today; this project's own doctrine is that that is not the question.
