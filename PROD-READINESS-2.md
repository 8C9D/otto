# PROD-READINESS-2 — Otto, round 2

Bounded remediation of a frozen list, 2026-08-10, branch `prod-readiness-2/2026-08-10`, from commit `7a3cf54` on `prod-readiness/2026-08-10`.

Baseline artifact: `reviews-2/BASELINE-2.md`. Review trail: `reviews-2/`.

**This is not a discovery sweep.** Every item below was found, evidenced and adversarially reviewed in round 1 (`PROD-READINESS.md`, `reviews/`). Round 2's only job is to close a named subset honestly and to say plainly what it could not close. Nothing here supersedes round 1's record; that record is not edited.

Round 1's terminal states, scope constraint, and schema freeze at V3 all still bind.

---

## Baseline

`scripts/verify.sh` at `7a3cf54`, from a clean clone: **exit 0 — OttoDomain 246, OttoPersistence 113, OttoUI 174, total 533**, `swiftlint --strict` clean.
Simulator suite from `Packages/OttoUI/`: exit 0, `** TEST SUCCEEDED **`, **101 / 65 / 20 tests, 7 known issues**.

Both reproduce the round-1 prediction exactly. Full output and the environment table are in `reviews-2/BASELINE-2.md`.

**One environment fact changed and it is load-bearing.** Round 1 recorded a non-Gregorian device calendar as unobservable on this host and deferred F1 partly for that reason. It is observable: a swift-testing bundle launched directly with `-AppleLocale th_TH@calendar=buddhist` runs with `Calendar.current.identifier == .buddhist`. Measured before this run touched code; see `reviews-2/BASELINE-2.md`.

---

## THE WORK LIST — frozen by the round-2 prompt

Seven items, in the order given. Everything else in round 1's NEXT ROUND stays in NEXT ROUND.

| # | id | what | terminal state |
|---|---|---|---|
| 1 | **F1** | The calendar defect, both ends together | **RESOLVED** — `a82d4e0` + `4b18420`; see F1 below for the two boundaries it does **not** cover |
| 2 | **R4-1** | An authorized user with a failing engine sees a Today identical to a healthy one | **RESOLVED** — `eb4a13b` + `12fdcfc` + `c566ce6` |
| 3 | **R0-6** | `reconstructWatermarksNow` leaves a resurrected-after-tombstone subscription with a nil watermark | **RESOLVED** — `db13abd` + `8ea8162` |
| 4 | **R3-1** | `current.isEmpty` counts tombstones, so an all-tombstoned database reproduces F6 | **RESOLVED** — `20d189a` |
| 5 | **R0-4** | `mappingLogger` can log a trial conversion amount and a raw vendor URL | **RESOLVED** — `0b76d65` |
| 6 | **RF-3** | Failed-`add` reasons for failures 2..n reach neither log nor caller | *(pending)* |
| 7 | **R5-2** | F2's log line has no executable guard | *(pending)* |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded). There are no others.

## REVIEW RANGES

Round 1's `RF-2` was a systematic blind spot: each stage's range started at whatever HEAD happened to be, so four commits — including two review-mandated remediations — were never inside any review's range. This run records the exact range handed to each reviewer, and each range starts at the **previous stage's reviewed head**, not at the current HEAD.

| stage | range passed to the reviewer | reviewed head | verdict |
|---|---|---|---|
| 0 | — (baseline only, `a15336a`) | — | no review |
| 1 — F1 | `7a3cf54..a82d4e0` | `a82d4e0` | **PASS-WITH-FINDINGS** (`reviews-2/REVIEW-1.md`) |
| 2 — R4-1 | `a82d4e0..100c508` | `100c508` | **PASS-WITH-FINDINGS** (`reviews-2/REVIEW-2.md`) |
| 3 — R0-6 | `100c508..62b4128` | `62b4128` | **PASS-WITH-FINDINGS** (`reviews-2/REVIEW-3.md`) |
| 4 — R3-1 | `62b4128..989ece0` | `989ece0` | **PASS-WITH-FINDINGS** (`reviews-2/REVIEW-4.md`) |
| 5 — R0-4 | `989ece0..<head>` | *(pending)* | *(pending)* |

**The range start is recorded when the stage opens, not when its verdict lands.** Four consecutive reviewers raised the missing row, each time because the table was being kept as a record of *completed reviews* rather than of *ranges issued* — which is round 1's `RF-2` in miniature, in the table built to prevent it. The start is knowable from the stage's first commit; only the head and the verdict have to wait.

Stage 0's commit is deliberately inside stage 1's range rather than being treated as a reviewed parent, so no commit in this run is a range boundary that nobody read. Stage 1's own remediation commit lands **after** the reviewed head `a82d4e0` and is therefore inside stage 2's range, not orphaned between them.

---

## ASSUMPTIONS

1. **The device calendar is Gregorian for both real users.** Undeterminable without touching the device, which is prohibited. Carried forward unchanged from round 1.
2. **Adding a SwiftLint `custom_rules` entry counts as touching `.swiftlint.yml` and is therefore not done.** The scope constraint says "Never weaken a lint rule to land a change … do not touch `.swiftlint.yml`". Adding a *stricter* rule is the opposite of weakening one, and `reviews/REVIEW-2.md:140-142` explicitly recommends that route as this repository's own idiom for exactly this defect class. The instruction is ambiguous as applied; the conservative reading is that the file is off limits, so no lint rule was added and the resulting guard gap is stated per item rather than closed.
3. **Release configuration behaves as Debug** except where a finding says otherwise. No Release build was produced this run.
4. **`7a3cf54` is the intended starting point** and round 1's branch is never to be merged, rebased or pushed by this run.

## CANNOT ASSESS

- Whether the real `UNUserNotificationCenter` daemon preserves an explicitly attached Gregorian calendar across the archive/restore round trip on a **device**. Simulator evidence is recorded per item; hardware is prohibited.
- Real notification delivery, Focus breakthrough, interruption levels. Requires hardware.
- Release-configuration behavior of any kind.
- Accessibility-label rendering. No AX client on this host.

---

## ITEM 1 — F1, the calendar defect at both ends

**RESOLVED**, `a82d4e0`, remediated after `reviews-2/REVIEW-1.md`.

**Reconfirmed at HEAD before any edit.** All five sites reproduce at `7a3cf54`: `DateProvider.swift:34`, `DisplayFormatting.swift:33,40,57`, `CalendarDayBinding.swift:7`, `InsightsView.swift:142` read through `Calendar.current`; `LiveNotificationClient.swift:226-232` builds the trigger from a bare `DateComponents` with no calendar.

**What changed.** `CalendarDay.conversionCalendar` in `OttoDomain` — the only module all three OttoUI targets can see, which is where `reviews/REVIEW-2.md` finding 4 said it had to live. Gregorian identifier, **autoupdating** timezone. The five reading sites take it as their default; `LiveNotificationClient.add` attaches it to the trigger components.

**Why the timezone is autoupdating, measured.** `Calendar(identifier:)` alone carries a snapshot of the zone in force when it was built. Against real `UserNotifications`:

| trigger components | TZ unset (Toronto) | `TZ=Asia/Tokyo` |
|---|---|---|
| bare, nil calendar (pre-fix) | `2027-03-15 13:00Z` | `2027-03-15 00:00Z` |
| Gregorian + autoupdating zone (shipped) | `2027-03-15 13:00Z` | `2027-03-15 00:00Z` |
| Gregorian + pinned Tokyo (rejected) | `2027-03-15 00:00Z` | `2027-03-15 00:00Z` |
| after `NSKeyedArchiver` round trip | `2027-03-15 13:00Z` | `2027-03-15 00:00Z` |

The shipped form is instant-identical to the pre-fix one in both zones. `reviews/REVIEW-2.md:105` named this trap specifically.

**Readback verified explicitly.** `pendingRequests()` returns year/month/day/hour/minute unchanged and `dateComponents.timeZone` is still `nil`, so the pre-existing `pendingRoundTrip` and `addTranslatesCalendarTrigger` guards still hold and the reconcile diff does not churn. The attached calendar also survives `NSKeyedArchiver` secure coding with the autoupdating zone intact.

**Verification — round 1's stated reason for deferring F1 does not survive.** `PROD-READINESS.md:133` records the complete fix as "unverifiable on this host by construction". Both routes the round-2 prompt named work:

1. **Host test process.** `swiftpm-testing-helper … -AppleLocale th_TH@calendar=buddhist` (with `DYLD_FRAMEWORK_PATH` set to the macOS platform frameworks) runs the real bundle with `Calendar.current.identifier == .buddhist`. Also exercised under `ar_SA@calendar=islamic-umalqura` and `ja_JP@calendar=japanese`.
2. **Simulator.** `xcodebuild test -testLanguage th -testRegion TH` from `Packages/OttoUI/` puts the iOS Simulator test process into the Buddhist calendar. Confirmed genuinely Buddhist by `DisplayFormattingTests.swift:49` rendering `"Aug 15, 2569 BE"` there. The F1 guards pass in that run.

Route 2 exercises the **real framework types** — `UNCalendarNotificationTrigger`, its component normalization and `nextTriggerDate()` — which is the code F1 turns on. It does **not** exercise `UNUserNotificationCenter`, the daemon, or their archive/restore round trip: the tests inject `FakeUserNotificationCenter`. That boundary is under CANNOT ASSESS.

**Falsified, at both ends and at every site.**

| what was reverted | host | result |
|---|---|---|
| the trigger line only | Gregorian | `(trigger.dateComponents.calendar?.identifier → nil) == (.gregorian)` fails |
| all five sources to `7a3cf54` | Buddhist | 5 F1 issues: `DateProvider.live` reads 2569; `displayDate() → 1483-08-15 05:17:32 +0000` against `2026-08-15 04:00:00 +0000`; `displayText` renders `"Aug 15, 2026 BE"` where the day's own instant renders `"Aug 15, 2569 BE"`; trigger calendar nil; **`nextTriggerDate() → nil`** |
| `calendar.timeZone = .autoupdatingCurrent` only | Gregorian | its own guard fails — and `TimeZone.autoupdatingCurrent == TimeZone.current` is **false** here, so the assertion is not already true for an unrelated reason |
| `asDate`, `monthText`, `spokenText` defaults (remediation) | Buddhist | 4 issues, including **`(stored → 2569-08-15) == (day → 2026-08-15)`** — the DatePicker write path putting an era-numbered year into billing data |

That `nextTriggerDate() → nil` is the partial fix proved: a Gregorian year handed to a bare trigger on a Buddhist device schedules a reminder that can never fire. It is why both ends had to move together.

### The two things this fix does NOT do

**1. It does not repair data already stored under a non-Gregorian device calendar, and on such a device it makes matters worse until that repair exists.** This is round 1's **R0-7**, which is on round 1's NEXT ROUND list and which round 2 is forbidden to touch — but the consequence was not written down, and `reviews-2/REVIEW-1.md` finding 2 is right that the commit message reads as though it were.

Traced through the code rather than assumed. On a Buddhist device holding pre-fix data, stored anchors are era-numbered (2569). After this fix `DateProvider.live.today()` returns 2026, `horizonEnd = today.adding(days: 90)` (`NotificationScheduler.swift:16,76`) is a 2026 day, and every stored date is ~543 years beyond it. So **no reminder is planned at all** — not, as the review states it, a trigger 543 years out — while `materializeEvents` caps at `min(storedWatermark ?? today, today)` and produces no rows. `ledgerFailures` stays empty, so `canClaimCoverage` is `true` and Today states `coveredThrough` at the 90-day horizon over zero scheduled reminders.

Before this fix that device delivered, because the two errors cancelled. **F1 must not reach a non-Gregorian device that already holds data until R0-7's repair ships.** On a fresh install of any calendar, and on every Gregorian device, the fix is correct — and ASSUMPTION 1 holds both real users' devices to be Gregorian, where this change is a strict no-op.

**2. The reading sites have no CI-executable guard.** By ASSUMPTION 2 no SwiftLint `custom_rules` entry was added, so nothing fails on a Gregorian runner if `Calendar.current` returns to those defaults. What exists instead: eight guards that fail under the documented non-Gregorian harness, and a statement of that limitation in `CalendarEraTests.swift` itself so no green CI run is mistaken for evidence about F1.

### Corrections to stage 1's own commit message

`a82d4e0`'s message overstates four things. Recorded here because commit messages cannot be amended and the ledger is the live document.

- **"all 16 guards pass … and on the simulator"** — the guards do pass in all four environments, each confirmed individually. The **runs** exit non-zero: 1 issue under `th_TH@calendar=buddhist` and `ja_JP@calendar=japanese`, 5 under `ar_SA@calendar=islamic-umalqura`, and `** TEST FAILED **` / exit 65 on the Simulator. **Every one of those failures is pre-existing**, reproduced at `7a3cf54` on the same hosts, so the stage regresses nothing — but the record read green and was not.
- **"16 guards"** was the test count of the filtered run (`Test run with 16 tests in 2 suites`), not a count of new assertions. The diff adds 6 tests and 14 assertions at `a82d4e0`, plus 4 tests in the remediation.
- **"5 issues"** in the five-source Buddhist falsification: the command prints **6**, the sixth being the pre-existing `DisplayFormattingTests.swift:49`.
- **"against real iOS UserNotifications"** overstates a run that injects a fake center. Real framework types, not the subsystem.

`LiveNotificationClient.swift`'s comment cited `reviews-2/REVIEW-1.md` — a file that did not exist at commit time and is the reviewer's output, not the builder's. Repointed at this ledger.

---

## ITEM 2 — R4-1, an authorized user with a failing engine sees a healthy Today

**RESOLVED**, `eb4a13b`. This is the one item with a scope exception permitting new user-facing copy.

**Reconfirmed at HEAD.** `TodaySection.plan` at `7a3cf54` emits `.notificationStatus` only for a permission other than authorized, and `.coverage` only when `canClaimCoverage`. Measured with a throwaway probe against the real `plan`, then deleted:

```
healthy       : [needsAction, next30Days, coverage]
ledger failed : [needsAction, next30Days]
pass failed   : [needsAction, next30Days]
```

Both failing states carry **no notification surface at all** — the coverage line is simply absent, and a user cannot notice the absence of a sentence they have never been shown.

**What changed.** A `.coverageGap` section, rendered as `CoverageGapCard` in the aggregate-card shape `unreadableRecordsSection` established (the precedent the scope exception names). It states that reminders could not be updated and how many subscriptions it touched — **a count, never a vendor or an amount**; `ledgerFailures` carries only UUIDs, so naming anything else would have meant going and fetching it.

Two wordings, because a whole failed pass has no per-subscription count and "0 subscriptions couldn't be updated" is not what happened:

- some ledgers failed → *"3 subscriptions couldn't be updated"* / *"Otto couldn't refresh their reminders on its last check, so some may be missing. Nothing was deleted, and it will try again."*
- the pass failed outright → *"Reminders couldn't be updated"* / *"Otto's last check didn't finish, so some reminders may be missing. Nothing was deleted, and it will try again."*

**The one piece of new state, and why it is needed.** `outcome == nil` meant two opposite things — "no pass has run yet" and "the last pass failed" — and a warning that cannot tell them apart fires on every cold start. `NotificationStatusStore.lastPassFailed` is derived inside `apply` as `outcome == nil`, so there is exactly one line where it can disagree with itself. No new setting, no new screen, no new navigation, **no SwiftData anything**.

**Predicted and confirmed observable difference.** Healthy authorized: unchanged. Fresh launch before the first pass: unchanged — no card. Denied / not-determined: unchanged, `.notificationStatus` already says something truer. Empty database: unchanged. Authorized or provisional with a failed pass or a failed ledger: the new card, where previously nothing.

**Falsified.**

| what was reverted | result |
|---|---|
| `plan`'s `.coverageGap` branch | `(ledgerFailed → [needsAction, next30Days]).contains(.coverageGap)` fails, plus the provisional and pass-failed cases — 3 issues. The failure message *is* the finding. |
| `lastPassFailed = outcome == nil` in the store | `(store).lastPassFailed → false` after a failed pass |
| a fixed `.frame(height: 44)` on the card | `(accessibility → 44.0) > (regular * factor → 66.0)` fails in both wordings |
| `TodaySection.input`'s read of the store | `.lastPassFailed → false` and `plan → [needsAction]` after a pass that threw |
| the two wordings swapped | `(card.headline → "0 subscriptions couldn't be updated")` — the exact sentence this branch exists to prevent |

The last two were added in remediation. `reviews-2/REVIEW-2.md` finding 1 was right that the first three did **not** reach the wiring: an earlier draft of this section claimed they did, while `TodaySection.Input`'s construction was still a private method on a `View`, and the reviewer deleted the whole notification half of it with all 185 tests green. `TodaySection.input` is now a static factory over the stores, and `CoverageGapCard.headline`/`.detail` are no longer private — the same treatment `InsightsView.monthText` got one stage earlier, for the same reason.

**The wiring took three attempts, and the first two claims about it were wrong.** `reviews-2/REVIEW-2.md` finding 1 showed the original falsifications never reached the view; the remediation extracted `TodaySection.input(overview:…)` and this ledger then called *that* "the wiring", which `reviews-2/REVIEW-3.md` finding 2 showed was still a helper the test calls directly — `notifications: model.notifications` could still be replaced with `nil`, deleting the permission banner, the coverage sentence and the gap card at once, with every test green. `c566ce6` moved the argument choice into `TodaySection.input(model:overview:subscriptionsEmpty:)`, and `reviews-2/REVIEW-4.md` finding 3 then showed the guard covered only the one argument the review had named, so the other two could be replaced with constants and Today silently lost its unreadable-record and read-repair cards. All three model reads are asserted now.

Each extraction closed the shape it was pointed at and left the next one. That is worth stating plainly rather than as three separate corrections: **a guard written from the failure it is answering closes exactly one argument.**

**Still unguarded, stated rather than papered over.** Nothing in the tree renders `TodayView`, so `coverageGapSection`'s one-line body can be replaced with `EmptyView()` and every test stays green. Closing that needs a view-hosting test for `TodayView`, and on this host it could only assert that it does not crash — the accessibility tree that would let it assert the card *appears* is exactly what this machine does not vend, which is why `EmptyStateTests` carries 7 known issues. Recorded as a residual, not as an environment excuse.

**What is NOT verified.** The *rendered strings* are not asserted: this host vends no accessibility tree, which is the same limitation `reviews/BASELINE.md` recorded and why `EmptyStateTests` has 7 known issues. What the simulator does prove is that the card renders and grows correctly at `.accessibility5` in both wordings.

**The card fires for every trigger except one, and that one is pre-existing.** `rescheduleSoon` reports a failure as `onOutcome?(nil)`, so `.foreground`, `.timeZoneChange`, `.significantTimeChange`, `.notificationDelivered` and `.notificationAction` all set the flag, and `appDidBecomeActive` runs a fresh pass on every foreground — so a persistent failure surfaces the next time the user opens the app. `handleBackgroundRefresh` never calls `onOutcome` on either path, so a failed `BGAppRefreshTask` pass still publishes nothing. That is round 1's **R4-2**, unchanged by this item and still in NEXT ROUND; the coordinator is inside `#if os(iOS)` and compiles to nothing under host `swift test`, so that wiring remains untested.

**A file was split rather than a lint rule relaxed.** The card pushed `TodayView.swift` past SwiftLint's 400-line `file_length`. Reconstructing the unsplit file at the stage's end gives **456** lines, and SwiftLint confirms it: `File should contain 400 lines or less: currently contains 456`. (An earlier draft of this paragraph said 440, a number measured at an intermediate working state and never re-derived — the same class of defect `reviews-2/REVIEW-1.md` finding 5 raised, recurring in the document written to correct it.) `.swiftlint.yml` is untouched; `TodaySection` moved to `TodaySectionPlan.swift`, which is the seam the type already documents — the pure composition decision, holding no view, and the thing `TodaySectionPlanTests` exercises.

---

## ITEM 3 — R0-6, a resurrected subscription comes back with no watermark

**RESOLVED**, `db13abd` + `8ea8162`.

**Reconfirmed at HEAD.** `reconstructWatermarksNow` (at `7a3cf54` in `OttoStore+DataTransfer.swift`; moved to `OttoStore+Watermarks.swift` by this stage's own split) fetches subscriptions with `deletedAt == nil`, deletes **every** watermark row unconditionally, then rebuilds one only for the subscriptions in that live fetch. A subscription tombstoned at reconstruct time therefore ends with no row; `ImportResolution` can clear `deletedAt` on a later merge and bring it back; `OttoStore+BillingEvents.swift:54`'s `min(storedWatermark ?? today, today)` then materializes from **today**. That is the founding v2.1 hazard and F6's exact failure signature by a second route.

**What changed.** One line: the fetch drops its predicate and reconstructs for every subscription, tombstoned ones included. The **event** fetch still filters to live rows, so a tombstoned subscription falls back to its anchor rather than inheriting a dead ledger's progress — the same conservative value a live subscription with no ledger rows already gets. The v2.5 cap (`min(reconstructed, current[id] ?? reconstructed)`) is untouched, so no watermark can move forward.

**No schema change.** `StoredMaterializationWatermark` is unchanged; this is a source change in `Packages/OttoPersistence/Sources/`, which round 1 had left untouched. The cost is one device-state row per tombstoned subscription, never read while it stays tombstoned.

**An existing assertion changed, deliberately and in the strengthening direction.** `DataTransferTests` asserted `materializationWatermark(forSubscription: fixtureUUID(4)) == nil` under the comment *"A tombstoned subscription materializes nothing and needs none."* That reasoning is true only while the subscription stays tombstoned, which is precisely R0-6's point. The assertion now pins a **value** — the anchor, `2026-03-01` — rather than an absence. No test was skipped, disabled, or weakened.

**Falsified.** Reverting the fetch predicate produces exactly 2 issues, both watermark assertions and nothing else:

```
✘ "watermarks reconstruct from the ledger…" DataTransferTests.swift:262
✘ "⛔ a subscription tombstoned at reconstruct time and resurrected later still has a watermark"
   RestoreIntoEmptyStoreTests.swift:116
✘ Test run with 114 tests in 23 suites failed with 2 issues.
```

The first falsification attempt was **invalid and is recorded rather than hidden**: the bare fetch line appears twice in the file, and patching the first occurrence broke `completeSnapshot` instead, producing `danglingReference` and tombstone-snapshot failures that had nothing to do with the fix. Re-done against the line inside `reconstructWatermarksNow`.

**What this does NOT do.** `reviews/REVIEW-0.md` names *three* filters between a subscription and a rebuilt watermark, and this removes one. The other two survive at `OttoStore+Watermarks.swift`: `guard let id = subscription.id, let reconstructed = latestBySubscription[id] ?? subscription.cycleStartDay else { continue }`. They are **inert**, and the completeness argument is: a record with a nil `id` or a nil `cycleStartDay` cannot map to a domain `Subscription` at all — `SubscriptionMapping` routes both through `require(...)` / `CalendarDay.stored(...)` and `StorageShapes` throws `MappingError` on nil — so it is skipped by `mapSkippingFailures`, counted in `unreadableCount`, and can never reach `materializeEvents`. **For every subscription that can materialize at all, the fix guarantees a row.** That is the statement the item should have made without a reader deriving it.

**A lint regression, caught and repaired inside the stage.** `db13abd` pushed both `OttoStore+DataTransfer.swift` and `DataTransferTests.swift` to 403 lines, past the 400-line `file_length`. `.swiftlint.yml` is untouched; `8ea8162` split the watermark reconstruction and the §5.3 dirty flag into `OttoStore+Watermarks.swift` (the seam is the store they write — those methods own the `deviceState` context while the rest writes the main one) and the empty-store restore suite into `RestoreIntoEmptyStoreTests.swift`. `markRestoreDirty` loses `private`, which is file-scoped, because `restoreThroughMainSave` still calls it.

### Corrections to this stage's own record

- **`db13abd`'s message ends "swiftlint --strict clean" and that commit is not.** It carries two `file_length` errors at 403 lines, repaired two commits later by `8ea8162`. The ledger recorded the repair and not the false claim. Commit messages cannot be amended, so the correction lives here.
- **This stage regressed the non-Gregorian baseline it had just documented, from 5 issues to 7 under `ar_SA`, and it is now repaired.** `CoverageGapCardTests` pinned the ASCII literals `"1 subscription couldn't be updated"` / `"3 subscriptions…"`, which render as `"١ subscription…"` under a locale with its own numbering system — the *same* defect class this run had diagnosed four paragraphs earlier as N2-1. The assertions now compare against `subscriptionCountText(n)` and pin the branch by structure (`one.headline != three.headline`, suffix, count phrase present) rather than by ASCII digits. Re-measured after the repair: **1 / 1 / 5** under `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura` — the documented baseline exactly.
- **The R0-6 falsification cited a file layout this stage deleted.** `DataTransferTests.swift:397` is `RestoreIntoEmptyStoreTests.swift:116` after the split, and `reconstructWatermarksNow` is no longer in `OttoStore+DataTransfer.swift`. Both corrected above. This is the third recurrence of a citation measured before a move and not re-derived after it.

**Unrelated stderr, checked.** The persistence suite prints `CoreData: error:` lines about a model checksum and `deviceStateStoreUnavailable`. They appear identically with the fix present and reverted, and the suite passes in both, so they are pre-existing diagnostics from a deliberate migration-failure test, not a regression.

---

## ITEM 4 — R3-1, an all-tombstoned database still loses its watermarks

**RESOLVED**, `20d189a`.

**Reconfirmed at HEAD.** `ExportService.performImport` decided the watermark policy with `strategy == .replace || current.isEmpty`, and `OttoDataSnapshot.isEmpty` is emptiness of the raw arrays, which `completeSnapshot()` fills **tombstones included** by design. A database whose every record is tombstoned is therefore not `isEmpty`: the UI asks merge-or-replace, and answering Merge maps to `watermarks: .keep`, leaving every restored subscription with a nil watermark. `min(storedWatermark ?? today, today)` then materializes from today and the rows between the file's last charge and today are silently never created — F6 exactly, one prompt later.

**What changed.** `OttoDataSnapshot.hasNoLiveSubscriptions` in `OttoDomain`, and the policy reads it instead of `isEmpty`. The predicate **strictly widens**: `isEmpty` implies it, so every input that reconstructed before still does.

**Subscriptions, and only subscriptions — corrected after `reviews-2/REVIEW-4.md` finding 1.** The predicate first shipped requiring *all five* record arrays to be tombstone-only, and that missed the state a user actually reaches. `deleteSubscription` cascades the tombstone to trials, episodes, billing events and price changes, but **not** to payment methods, which are not children of a subscription. So a device that deleted every subscription and kept its card answered "something is live", took `.keep`, and lost its watermarks — R3-1's own failure, verbatim, on the likeliest path to it. The reviewer measured it, and also measured that two of the three survivors the first draft named (price change, cancellation episode) cannot survive a delete at all. A watermark is per-subscription, so no other record type can carry ledger progress; the faithful predicate is the one-conjunct one.

**Second-order effect, disclosed.** `restore` passes `markingDirty: watermarks == .reconstruct`, so an all-tombstoned merge now also writes and clears a §5.3 restore dirty flag where `.keep` wrote none, and acquires that path's double-fault window. Benign here — there is no watermark to strand on such a database, the end state is flagless under both policies, and round 1 already renamed the invariant test for the policy rather than the strategy — but this is the second time a widening of this predicate has moved the dirty-flag branch without the ledger saying so (`reviews/REVIEW-3.md` finding 3 raised it the first time).

**The prompt is deliberately left alone.** `ImportPreview.databaseIsEmpty` still uses `isEmpty`, so `SettingsView` still asks merge-or-replace for an all-tombstoned database. That is right: a tombstone is communicable data and a replace really does treat it differently from a merge. What was wrong was only the **watermark** decision following the record count instead of the principle round 1 stated for it — *"does this device have ledger progress worth keeping"*. Those are two different questions and they now have two different expressions.

**Falsified in three directions**, so the predicate cannot be satisfied by a constant either way:

| what was changed | result |
|---|---|
| back to `current.isEmpty` | the all-tombstoned test fails: `restoredWatermarkPolicies == [.reconstruct]` |
| pinned to `true` | the ordinary merge test fails: `restoredWatermarkPolicies == [.keep]` |
| `hasNoLiveRecords` forced to `false` | both the all-tombstoned **and** the empty-database tests fail — confirming the empty case now routes through the same predicate |

**Proved against the real store, not only against the policy.** Round 1's Review 3 rejected a decision-variable assertion as one link short of its claim, so `RestoreIntoEmptyStoreTests` gains an end-to-end case: an all-tombstoned store restored with `.keep` leaves the watermark **nil**, and the same store with the same file under `.reconstruct` gets `2026-06-15`, the latest live imported row.

**What this does NOT do.** The merge-or-replace prompt is unchanged, so an all-tombstoned database is still asked the question; only the watermark answer changed. The import still cannot distinguish a user who deliberately deleted everything from one recovering a reinstall — both answer Merge into a subscription-less device and both now reconstruct, which is the safe direction but not a read of intent.

---

## ITEM 5 — R0-4, the persistence log can carry an amount and a vendor URL

**RESOLVED**, `0b76d65`.

**Reconfirmed at HEAD.** `mappingLogger` is declared outside `OttoLog` entirely (`OttoStore.swift`), and both of its call sites interpolated `String(describing: error)` of a whole `MappingError`. `.invalidValue` carries the offending value, and two throw sites put user financial content in that slot: `SubscriptionMapping` throws `"\(lengthDays)/\(bufferDays)/\(convertsTo)"`, where `convertsTo` is a **trial conversion amount**; `URL.storedOptional` throws the raw string, reached for `vendorURL` and `cancellationURL` — **which vendor**.

**What changed.** `MappingError.logSummary` renders the same fact with the value withheld, and `mappingLogSummary(_:)` extends that to any error — a `MappingError`'s summary, or any other error's **type name**, which is the convention F2's line already uses. Both call sites take it: `OttoStore.mapSkippingFailures` and `CancellationEpisodeMapping.storedNoteAnywhere`. `description` is deliberately unchanged: a thrown error still carries the value to a caller entitled to it, and only the **log** is redacted.

**Marked `.public`, deliberately.** Entity and field names are schema constants, so the redacted line is safe to read — and it is now *more* useful than what it replaced. The pre-fix line rendered `Skipping unmappable record: <private>`, which told an investigator nothing at all; the fix says which field of which entity failed.

That `<private>` is the whole point of the finding. Round 1 rated R0-4 P2 partly because `Logger` interpolation defaults to `.private`, so the amount was redacted on display. This project's own doctrine rejects that reasoning (`OttoLog`: *".private redaction is a display rule, not a guarantee about what was written"*), and a sysdiagnose is readable by anyone holding the device.

**An executable guard, using the technique round 1 recorded as impossible.** `OSLogStore(scope: .currentProcessIdentifier)` reads only this process, so the test asserts about the app's code rather than about the host. `reviews/REVIEW-5.md` demonstrated this and round 1 declined it on cost; the cost is real and is recorded below.

**Falsified in both directions.**

| what was broken | result |
|---|---|
| the **call site**, back to `String(describing: error)` | the emitted line becomes `Skipping unmappable record: <private>` — the field assertion fails and the `<private>` assertion fails |
| `logSummary`, made to interpolate the value again | the emitted line becomes `… holds an invalid value "20260230"` in **plaintext**, because the summary is `.public` — 3 issues across both the unit and the emission tests |

Together those pin it from both ends: the call site must use the helper, and the helper must withhold the value.

**Costs and limits, stated.** The `OSLogStore` read takes the OttoPersistence suite from ~1.5 s to ~7 s. The first version of the emission test was **flaky by construction** — it took the *first* skip line in the time window, and the log is process-wide, so a concurrently running suite's line was picked up instead (observed: `StoredSubscription.status is missing`). It now examines every skip line in the window and asserts the value is absent from **all** of them, which is both stable and stronger. What the guard cannot show on this host is that the raw value never entered the log buffer: pre-fix it rendered `<private>`, so the write is invisible to a reader without a private-data profile. What it does show is that the code path now writes only the summary.

---

## NOT DEFECTS

*(a finding that no longer reproduces at HEAD is moved here with its evidence rather than fixed)*

- Nothing yet. All seven work-list items reconfirmed at HEAD so far.

## DEFERRED

*(populated per stage)*

## NEXT ROUND

Carried forward from round 1 and not touched by round 2, plus what round 2 discovered. The full list is reconciled at the end of this document.

### Discovered by round 2

- **N2-1 (P2, from stage 1)** — five tests pin rendered strings that a non-default locale legitimately writes differently, so they fail under the non-Gregorian harness. All five are **pre-existing** — reproduced identically at `7a3cf54` — and invisible until this run created such a host. They are over-specified assertions, not product defects. **They divide into two unrelated causes, and the first version of this entry got three of them wrong:**
  - **Calendar-caused, 2 tests.** `DisplayFormattingTests.swift:49` and `NotificationReconciliationTests.swift:170`. `Date.FormatStyle` renders through the process calendar and a `.locale()` call does not override it. Only `:49` fails on **any** non-Gregorian host — it pins a year (`"Aug 15, 2569 BE"` under Buddhist, `"Aug 15, Reiwa 8"` under Japanese). `:170`'s body carries a month and a day and no year, so a calendar that agrees on those does not move it, and it fails under `ar_SA` alone. An earlier draft of this entry said both fail on any non-Gregorian host, which the per-host counts in the next paragraph already disproved.
  - **Numbering-system-caused, 3 tests, nothing to do with the calendar.** `DisplayFormattingTests.swift:59,68,69` render Arabic-Indic numerals under `ar_SA` — `"Every ٤٥ days"`, `"١ subscription"`, `"٣ subscriptions"` — through `String(localized:)` and `AttributedString(localized:)`, neither of which touches a date. They pass under `th_TH@calendar=buddhist` and `ja_JP@calendar=japanese`.

  So the per-host baseline is **1 issue** under Buddhist and Japanese, **5** under `ar_SA`, which is what this ledger and `CalendarEraTests.swift` record. Whoever picks this up is fixing two different things, not one.
- **N2-2 (P1, from stage 1)** — **R0-7 is now a prerequisite, not a follow-up.** F1 stops new corruption; a non-Gregorian device holding pre-fix data now plans zero reminders while Today claims coverage (mechanism traced under ITEM 1). R0-7 was rated P2 in round 1 as "the other half of F1". It is P1 the moment F1 ships to such a device. Required repair, concretely: for each stored day written under a non-Gregorian calendar, reinterpret the packed `yyyymmdd` by converting the era-numbered `(y, m, d)` back through the device calendar that wrote it into a Gregorian `(y, m, d)` — the inverse of `Calendar.current.dateComponents` — across `StoredSubscription` anchors and trial dates, `StoredBillingEvent.expectedDate`, `StoredCancellationEpisode` check dates, `StoredPriceChange.effectiveDate` and `StoredMaterializationWatermark.lastMaterializedThrough`. It needs a persisted marker of which calendar wrote the data, which the V3 schema does not carry — so it is a schema change and is **DEFERRED by the freeze**, exactly as round 1 concluded. A repair that guesses the writing calendar is not acceptable on billing dates.

