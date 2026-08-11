# REVIEW-3 — pass 3 (F6, data/restore), commit range `3f3e520..b15b0a6`

**VERDICT: PASS-WITH-FINDINGS**

The range is one commit, `b15b0a6`, touching two files: `ExportService.swift` (+15/-1) and `ExportServiceTests.swift` (+33).
It closes F6 exactly as the ledger's fix column scoped it — "reconstruct whenever the database was empty, independent of strategy" — with `let reconstruct = strategy == .replace || current.isEmpty` (`ExportService.swift:90`).

I did not take the fix on the strength of its unit test, which asserts only that a decision variable took a value.
I reproduced the whole chain against the **real store**: an empty database, a merge-resolved restore, and what each watermark policy then does to the rows the restore existed to bring back.
**The fix does what it claims.** Under `.keep` the restored subscription's watermark is nil and the charges between the file's last ledger row and today are silently never created; under `.reconstruct` the watermark comes back as the file's last live ledger row and those rows are created. That is F6's defect and F6's repair, measured, not argued.

The findings below are all P2. None of them is a defect in the committed behavior; they are gaps between what the commit message says is proved and what is actually proved, plus one residual of F6's shape that the fix does not reach and (post-freeze) must not.

---

## 1. Verification re-run here, not read from `BASELINE.md`

| measurement | BASELINE.md claims | re-derived at `b15b0a6` | result |
|---|---|---|---|
| `scripts/verify.sh` | 526 host tests (OttoDomain 246 / OttoPersistence 112 / OttoUI **168**), lint clean | **exit 0**; OttoDomain 246, OttoPersistence 112, OttoUI **169**, **total 527**; `xcodegen generate` ok; app target builds; `swiftlint --strict` clean | ✅ +1 test, nothing worse |
| simulator suite (`xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"`, run from `Packages/OttoUI/` per REVIEW-2's note) | 19 tests, 7 known issues, `** TEST SUCCEEDED **` | `✘ Test run with 19 tests in 3 suites passed after 7.832 seconds with 7 known issues` / `** TEST SUCCEEDED **`, exit 0 | ✅ identical |
| parent `3f3e520` is code-free | — | `git show --stat 3f3e520` = `PROD-READINESS.md` only; `git diff 406a5a6..HEAD --stat -- Packages/` = **only** `ExportService.swift` + `ExportServiceTests.swift`, which also confirms `b582d94` reverted pass 2 completely | ✅ the 168 baseline carries to the parent |

Commit-message claim "*Restored, 169 OttoUI tests pass (168 at baseline), lint clean*" — **reproduced exactly.**

## 2. Falsification re-performed, and then pushed further

**As the commit message describes it.** `|| current.isEmpty` removed from `ExportService.swift:90`, `swift test --package-path Packages/OttoUI --filter ExportServiceTests`:

```
✘ Test "a merge into an EMPTY database reconstructs anyway - the empty database is the recovery case"
   recorded an issue at ExportServiceTests.swift:141:9:
   Expectation failed: await transfer.restoredWatermarkPolicies == [.reconstruct]
✔ Test "a merge import restores the resolved snapshot and reports the counts" passed after 0.007 seconds.
✘ Test run with 7 tests in 1 suite failed after 0.007 seconds with 1 issue.
```

Both halves of the claim reproduce verbatim: the new test fails on that exact expectation, and the pre-existing non-empty merge test still passes.

**The falsification the message did not do, which I did.** A one-directional break can be satisfied by a constant, so I pinned the other side — `let reconstruct = true`:

```
✔ Test "a merge into an EMPTY database reconstructs anyway ..." passed after 0.010 seconds.
✘ Test "a merge import restores the resolved snapshot and reports the counts"
   recorded an issue at ExportServiceTests.swift:113:9:
   Expectation failed: await transfer.restoredWatermarkPolicies == [.keep]
```

So the pair of tests pins the predicate in **both** directions: it cannot be satisfied by hardcoding either policy.
This is stronger than the commit message claims for itself, and it is the right answer to this repository's documented "green assertion that means nothing" hazard at this seam.

Tree restored with `git checkout -- .` after each break; `git status --porcelain` empty at `b15b0a6` both times and at the end of this review.

## 3. The delegated proof — checked by running it, not by reading the claim

The new test asserts `restoredWatermarkPolicies == [.reconstruct]` against a `MockTransfer` whose `restore` records its arguments and whose `reconstructMaterializationWatermarks()` is `{}` (`ExportServiceTests.swift:19-27`).
That is a decision variable, not a behavior. The test doc and the commit message both say so, and delegate the behavior to `OttoPersistence`'s `DataTransferTests`.
The architectural reason is real and checked: `OttoUI/Package.swift:53-58` gives `OttoServicesTests` no dependency on `OttoPersistence`, and the header at `:1-8` makes `import OttoPersistence` there a compile error by design. There is no honest way to prove the store's behavior from this seam.

So I proved the composition myself, against the real store, in a temporary suite in `OttoPersistenceTests` (fresh in-memory containers, `exportData` → `importedSnapshot` → `resolveImport(strategy: .merge)` → `store.restore(...)`), then deleted it:

```
✔ POST-FIX: .reconstruct on the empty-database merge gives the ledger's last live row      (watermark == 2026-05-15)
✔ PRE-FIX:  .keep on the empty-database merge leaves the watermark nil                     (watermark == nil)
✔ POST-FIX consequence: the next pass materializes the Jun/Jul rows between the file's
             last charge and today                                                          (2026-06-15, 2026-07-15 created)
✔ PRE-FIX  consequence: with .keep the Jun/Jul rows are silently never created              (neither created)
✔ PROBE: a merge into an empty database leaves no dirty flag behind
✔ Test run with 5 tests in 2 suites passed after 0.196 seconds.
```

The fourth line is F6 itself, reproduced end to end on this host for the first time in this run, and the third line is its repair. **The fix is real.**

---

## Findings

### 1. P2 — the "proved against the real store" citation is one link short of the claim it carries

**severity:** P2. The claim is *nearly* true and the missing link holds when exercised (§3) — but it is the sentence that licenses a decision-variable assertion, so it has to say what it is claimed to say.

**evidence.**
Commit message and `ExportServiceTests.swift:122-126`: *"what `.reconstruct` then does to the stored watermarks is proved against the real store in OttoPersistence's DataTransferTests ('watermarks reconstruct from the ledger: latest LIVE row, anchor when none, never today')."*

That test is `DataTransferTests.swift:242-277`. Read at HEAD, it does two things the claim does not survive intact:

- It never goes through the policy. Line `:257` is `try await fresh.reconstructMaterializationWatermarks()` — the public repair entry point — not `restore(_:at:watermarks: .reconstruct)`, which is the argument this stage now passes. The link between them is `OttoStore+DataTransfer.swift:58-61`, two lines that no test in the tree asserts for its watermark effect.
- It never sees an empty database. Its fixture is `seedRichStore()` (`:14-61`), which saves five subscriptions, a ledger, episodes and **a pre-existing watermark** (`:23-25`) — and that pre-existing watermark is load-bearing for one of its expectations, because the v2.5 cap at `OttoStore+DataTransfer.swift:230` takes `min(reconstructed, current)`. The recovery case has no `current` at all, so the assertion that runs there is not the assertion this test makes.

`grep -rn "watermarks: .reconstruct"` over `Packages/OttoPersistence/Tests/` returns nine sites (`DataTransferTests.swift:96,108,152,173,221,236`, `RestoreDirtyFlagTests.swift:145,159`, `SyncPrerequisiteTests.swift:28,64,79`); **not one of them starts from an empty store, and not one of them asserts a watermark value after a `.reconstruct` restore.** The nearest thing to an end-to-end proof in the repository is `RestoreDirtyFlagTests.swift:66-81`, which is the *interrupted*-restore heal on a non-empty store.

Consequence, stated precisely: the committed suite went 168 → 169 without gaining a regression guard for the composition this stage's correctness rests on. Break `restore` so `.reconstruct` no longer reconstructs, and every test in the tree stays green — the new test asserts the argument, `DataTransferTests:242` calls the repair directly, and `RestoreDirtyFlagTests` reaches reconstruction through the dirty-flag heal instead. I verified this is a coverage gap and not a live defect by writing the missing test myself (§3); it passes today.

Closing it is a test-only change in `OttoPersistenceTests`, needs no schema change and no new capability, and is roughly the twenty lines I wrote and deleted.

**why the builder missed it.**
The seam boundary was read correctly — `OttoServicesTests` genuinely cannot reach the store — and then the search for the delegate stopped at the test whose *title* matches the sentence being written. The title does match. The fixture and the entry point do not, and neither was re-read against the specific claim ("what `.reconstruct` **then** does", i.e. the policy, on the path this commit creates).

### 2. P2 — the stated principle is broader than the predicate, and the uncovered remainder reproduces F6 exactly

**severity:** P2, and NEXT ROUND rather than this stage's work: it is a residual of F6's ledger scope discovered after the Review 0 freeze, not a defect introduced by this commit. Recorded so it is not lost.

**evidence.**
The commit message and the new comment at `ExportService.swift:79-82` justify the fix with a principle: *"The policy is about whether this device has ledger progress worth keeping, and an empty database has none."*
The predicate implemented is `current.isEmpty`, and `OttoDataSnapshot.isEmpty` (`OttoDataSnapshot.swift:28-31`) is emptiness of the **raw arrays**, which `completeSnapshot()` fills tombstones included (`OttoStore+DataTransfer.swift:8-11`, and `DataTransferTests.swift:116-122` asserts it).

A device whose every record is tombstoned has no ledger progress worth keeping either, and it is not `isEmpty`. Measured, in a temporary suite in `OttoPersistenceTests` (deleted afterwards):

```
✔ a database whose every record is tombstoned is NOT `isEmpty`, so it gets the prompt and can take .keep
    store.subscriptions().isEmpty == true      (nothing live)
    current.isEmpty            == false        (so SettingsView:293 asks the question)
✔ ...and a .keep merge into it restores the file with NO watermark - F6's outcome, one prompt later
    materializationWatermark(forSubscription: 1) == nil
    the 2026-06-15 and 2026-07-15 rows are not created
```

So the exact loss F6 describes survives this fix on a device that has deleted everything and then answers "Merge" at the prompt. It is narrower than F6 — it takes a deliberate user choice at an explicit prompt, not a silent default — which is why it is P2 and not P1. But the prompt asks about *records*, not about ledger progress, so the user is not consenting to this.

**why the builder missed it.**
The ledger's fix column says "reconstruct whenever the database was **empty**", and the diff implements that sentence faithfully. The commit message then generalizes the sentence into a principle without checking whether the predicate reaches as far as the principle does. The gap is between the two, not inside either.

### 3. P2 — an existing test's invariant statement is now false, in the one direction that matters for a crash

**severity:** P2, documentation-of-behavior only; the behavior itself is correct and I verified it.

**evidence.**
`RestoreDirtyFlagTests.swift:138` is titled *"a completed replace and a merge both end with no dirty flag — **a merge never writes one**"*.
Since this commit, a merge into an empty database takes `markingDirty: true` through `restore` → `restoreThroughMainSave` → `markRestoreDirty` (`OttoStore+DataTransfer.swift:58, 82-84`), so a merge now **does** write one, transiently, on exactly the recovery path.
The test still passes and passes for the right reason — its own store is non-empty (`:140-143`) and it only observes the end state — so nothing is green that should be red. I confirmed the end state is right for the new case too: the fifth probe in §3 shows no flag survives an empty-database merge.

This is worth recording rather than fixing: the transient flag is a *gain* (a crash between the two saves on the recovery path now self-heals instead of leaving nil watermarks), but the invariant sentence in that test name is the kind of stale claim this repository's history is made of.

**why the builder missed it.**
The blast-radius prediction in the commit message is about the *policy* ("a merge into a non-empty database is untouched"), which is true. The second-order effect — that the policy also selects the dirty-flag branch — is one call deep and is not visible in the diff.

### 4. Informational — the ledger does not record that this pass ran, and the Gate 3 procedure still says the defect is unfixed

Neither is a defect; both are bookkeeping that will mislead whoever reads next.

- `PROD-READINESS.md:152` still has F6's **terminal state** cell blank. F1's cell was filled in by `3f3e520`, so this document's own convention is that the cell is written per pass, not only at the end. Nothing is marked resolved without an artifact — this is the opposite error, an artifact without the mark — so no contract clause is broken.
- `docs/next-wave.md` (printed in full by `verify.sh`, and quoted in `BASELINE.md:127, 158`) still reads *"Recorded in §9a and `DECISIONS.md`; NOT fixed. Until it is fixed, the gate must be run by choosing Replace by hand."* Editing narrative documents is prohibited this run, so leaving it is correct — but Gate 3 is the manual gate whose "**Watermarks reconstructed from the ledger — UNMET**" criterion this commit exists to make passable, and the operator resuming it will read an instruction that is now obsolete.

---

## Checked and found clean (recorded so severity is not inflated by omission)

- **The fix does not relocate the bug.** In an empty database the delete loop at `OttoStore+DataTransfer.swift:214-221` iterates an empty fetch and the v2.5 cap at `:230` has no `current` to cap against, so `.reconstruct` is **strictly additive** relative to `.keep`: every live restored subscription gains a watermark and none is removed. R0-6's hole (tombstoned-then-resurrected returns with a nil watermark) is therefore not newly exposed — under `.keep` that subscription had a nil watermark too. The ledger already routes R0-6 to NEXT ROUND and says why; that remains correct.
- **`current.isEmpty` cannot be a masked read failure.** `completeSnapshot()` *throws* on an unmappable record rather than skipping it (`OttoStore+DataTransfer.swift:8-11, 19-28`; `DataTransferTests.swift:279-289` proves it), so an empty snapshot is genuinely an empty database, never a partial read. Had that read been lenient, `current.isEmpty` would have been a dangerous trigger.
- **The predicate cannot disagree with the UI that creates the case.** `SettingsView.swift:290-298` skips the merge-or-replace question on `preview.databaseIsEmpty`, which is `current.isEmpty` from the same `completeSnapshot()` (`ExportService.swift:51-59`), and `performImport` re-derives it from its own fresh snapshot (`:70`) instead of trusting the caller's earlier read. The two decisions are the same expression over the same source.
- **The consequence is consumed.** `AppModel.importData` (`AppModel.swift:256-261`) reschedules immediately after the import, and rescheduling materializes — so the reconstructed watermark is read by the very next pass, which is what my §3 probe exercises.
- **No SwiftData schema change.** The diff is two files, neither a model, a schema version, `OttoMigrationPlan`, nor `OttoContainerFactory`. `git diff --name-only 3f3e520..b15b0a6 -- .github/ Packages/*/Package.swift docs/ DECISIONS.md project.yml` is empty.
- **No prohibited action.** `406a5a6` is an ancestor of HEAD (no rewrite); `git reflog` shows ordinary commits plus one ordinary `revert`; `origin/main` is still at `406a5a6` and no remote branch contains HEAD (not pushed); no workflow, dependency, `project.yml`, or narrative-document change; no device contact, no network call, nothing in `<backup-dir>` touched — my own store probes ran on fresh in-memory containers via `OttoContainerFactory.inMemoryContainers()`.
- **No feature smuggled in.** No screen, toggle, export field, model, property, schema version, or config key. `reconstruct` is a local `let`; `ImportStrategy`, `RestoreWatermarkPolicy` and every public signature are unchanged.
- **No error handling that hides an error.** The diff adds no `try?`, no `catch`, no fallback; it changes one boolean.
- **No fabricated or unreproducible finding, and no severity inflation or deflation.** Every factual claim in the commit message was checked against the tree or re-measured: the strategy-to-policy coupling, `SettingsView`'s silent merge, the nil-watermark-materializes-from-today mechanism (`OttoStore+BillingEvents.swift:53-54`), "no new API, no new state, no schema change", "a merge into a non-empty database is untouched", the falsification, and the test counts. All hold. The one overreach is finding 1, and it is an overreach of a *citation*, not of a result.
- **The device half remains UNVERIFIED and is not claimed.** Gate 3's watermark criterion can only be met on hardware, which is prohibited this run; the commit message asserts nothing about the device.

## What this verdict means for the next stage

PASS-WITH-FINDINGS: the stage closes F6, the closure is verified against the real store rather than against a mock, the falsification is honest and reproduces exactly, and nothing is worse than `BASELINE.md`.

Carry forward:
- **Finding 1** should be closed inside this run if any later pass has room: one test in `OttoPersistenceTests` that restores into an **empty** store with `.reconstruct` and asserts the watermark, which is the guard the current 169 does not contain. If it is not closed, the ledger should say plainly that the empty-database restore has no committed regression guard.
- **Finding 2** joins **NEXT ROUND** with R0-6 — they are the same shape (a subscription that ends a restore with no watermark) and are the natural pair for the wave that owns this path.
- **Findings 3 and 4** are one-line records; 4 in particular matters to whoever resumes Gate 3.
