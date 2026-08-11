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
| 1 | **F1** | The calendar defect, both ends together | *(pending)* |
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
| 0 | `7a3cf54..<stage-0 head>` | — | *(no review; baseline only)* |

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

## NOT DEFECTS

*(populated per stage — a finding that no longer reproduces at HEAD is moved here with its evidence rather than fixed)*

## DEFERRED

*(populated per stage)*

## NEXT ROUND

Carried forward from round 1 and not touched by round 2. The full list is reconciled at the end of this document.

