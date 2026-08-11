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
| 2 | **R4-1** | An authorized user with a failing engine sees a Today identical to a healthy one | *(pending)* |
| 3 | **R0-6** | `reconstructWatermarksNow` leaves a resurrected-after-tombstone subscription with a nil watermark | *(pending)* |
| 4 | **R3-1** | `current.isEmpty` counts tombstones, so an all-tombstoned database reproduces F6 | *(pending)* |
| 5 | **R0-4** | `mappingLogger` can log a trial conversion amount and a raw vendor URL | *(pending)* |
| 6 | **RF-3** | Failed-`add` reasons for failures 2..n reach neither log nor caller | *(pending)* |
| 7 | **R5-2** | F2's log line has no executable guard | *(pending)* |

Terminal states are **RESOLVED** (with artifact evidence), **DEFERRED** (with reason), or **REJECTED TWICE** (reverted, objection recorded). There are no others.

## REVIEW RANGES

Round 1's `RF-2` was a systematic blind spot: each stage's range started at whatever HEAD happened to be, so four commits — including two review-mandated remediations — were never inside any review's range. This run records the exact range handed to each reviewer, and each range starts at the **previous stage's reviewed head**, not at the current HEAD.

| stage | range passed to the reviewer | reviewed head | verdict |
|---|---|---|---|
| 0 | — (baseline only, `a15336a`) | — | no review |
| 1 — F1 | `7a3cf54..a82d4e0` | `a82d4e0` | **PASS-WITH-FINDINGS** (`reviews-2/REVIEW-1.md`) |

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

### Corrections to this stage's own commit message

`a82d4e0`'s message overstates four things. Recorded here because commit messages cannot be amended and the ledger is the live document.

- **"all 16 guards pass … and on the simulator"** — the guards do pass in all four environments, each confirmed individually. The **runs** exit non-zero: 1 issue under `th_TH@calendar=buddhist` and `ja_JP@calendar=japanese`, 5 under `ar_SA@calendar=islamic-umalqura`, and `** TEST FAILED **` / exit 65 on the Simulator. **Every one of those failures is pre-existing**, reproduced at `7a3cf54` on the same hosts, so the stage regresses nothing — but the record read green and was not.
- **"16 guards"** was the test count of the filtered run (`Test run with 16 tests in 2 suites`), not a count of new assertions. The diff adds 6 tests and 14 assertions at `a82d4e0`, plus 4 tests in the remediation.
- **"5 issues"** in the five-source Buddhist falsification: the command prints **6**, the sixth being the pre-existing `DisplayFormattingTests.swift:49`.
- **"against real iOS UserNotifications"** overstates a run that injects a fake center. Real framework types, not the subsystem.

`LiveNotificationClient.swift`'s comment cited `reviews-2/REVIEW-1.md` — a file that did not exist at commit time and is the reviewer's output, not the builder's. Repointed at this ledger.

---

## NOT DEFECTS

*(a finding that no longer reproduces at HEAD is moved here with its evidence rather than fixed)*

- Nothing yet. All seven work-list items reconfirmed at HEAD so far.

## DEFERRED

*(populated per stage)*

## NEXT ROUND

Carried forward from round 1 and not touched by round 2, plus what round 2 discovered. The full list is reconciled at the end of this document.

### Discovered by round 2

- **N2-1 (P2, from stage 1)** — five tests pin rendered date strings that a non-Gregorian `Calendar.autoupdatingCurrent` legitimately writes differently, so they fail on any non-Gregorian host: `DisplayFormattingTests.swift:49,59,68,69` and `NotificationReconciliationTests.swift:170`. **Pre-existing** — reproduced identically at `7a3cf54` — and invisible until this run created a non-Gregorian host. They are over-specified assertions, not product defects: `Date.FormatStyle` renders through the process calendar and a `.locale()` call does not override it. Until they are fixed, the non-Gregorian harness has a non-zero baseline, which `CalendarEraTests.swift` now states.
- **N2-2 (P1, from stage 1)** — **R0-7 is now a prerequisite, not a follow-up.** F1 stops new corruption; a non-Gregorian device holding pre-fix data now plans zero reminders while Today claims coverage (mechanism traced under ITEM 1). R0-7 was rated P2 in round 1 as "the other half of F1". It is P1 the moment F1 ships to such a device. Required repair, concretely: for each stored day written under a non-Gregorian calendar, reinterpret the packed `yyyymmdd` by converting the era-numbered `(y, m, d)` back through the device calendar that wrote it into a Gregorian `(y, m, d)` — the inverse of `Calendar.current.dateComponents` — across `StoredSubscription` anchors and trial dates, `StoredBillingEvent.expectedDate`, `StoredCancellationEpisode` check dates, `StoredPriceChange.effectiveDate` and `StoredMaterializationWatermark.lastMaterializedThrough`. It needs a persisted marker of which calendar wrote the data, which the V3 schema does not carry — so it is a schema change and is **DEFERRED by the freeze**, exactly as round 1 concluded. A repair that guesses the writing calendar is not acceptable on billing dates.

