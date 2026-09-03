# BASELINE-5 - Otto production-readiness, round 5

Captured 2026-08-15 against commit `1b352f445bed02398514aba8650257fa884e1d0e` (branch `prod-readiness-5/2026-08-15`, created from `main` at its HEAD).

`1b352f4` is the merge of the round-4 stack into `main` (parents `cd9778c`, the CI-workflow commit, and `9e73378`, round 4's terminal HEAD).
This is the first round to start from `main` rather than from the previous round's branch.
The merge introduced nothing beyond the stack: `git diff prod-readiness-4/2026-08-12..main` is exactly one file, `.github/workflows/ci.yml`, 9 insertions.

Working tree was clean at preflight (`git status --porcelain` empty), and no commit precedes this file on the branch.

## Result: all five round-4 terminal figures reproduce exactly

| measurement | round-4 terminal (`8f3a979`, per `PROD-READINESS-4.md`) | re-derived here at `1b352f4` | result |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 597 tests (OttoDomain 261, OttoPersistence 127, OttoUI 209) | **exit 0**; OttoDomain **261**, OttoPersistence **127**, OttoUI **209**, total **597** | exact |
| `swiftlint --strict` | clean, 225 files | `Found 0 violations, 0 serious in 225 files` | exact |
| simulator suite | `** TEST SUCCEEDED **`, 119 / 72 / 53, 7 known issues | exit 0, `** TEST SUCCEEDED **`, **119 / 72 / 53**, `with 7 known issues` | exact |
| non-Gregorian harness | 1 / 1 / 5 issues | **1 / 1 / 5**, same five citations | exact |
| flake rate | 12 of 12 | **12 of 12 passed, 0 failed** | exact |

Every later "nothing worse than baseline" claim in this round is measured against: **597 host tests, lint clean under `--strict`, simulator 119 / 72 / 53 with 7 known issues, non-Gregorian 1 / 1 / 5, and 12 of 12 clean full OttoUI runs.**

## Provenance

From `git show-ref`, `git rev-parse` and `git diff`; no fetch or pull was run before the measurements.

```
1b352f445bed02398514aba8650257fa884e1d0e refs/heads/main
8806853a2df273175b82581eaa151a67cc58fbcd refs/heads/prod-readiness-2/2026-08-10
2d8913c4a80566347dcb067b0e261d3dc4342b05 refs/heads/prod-readiness-3/2026-08-11
9e7337892c4634f2feecad4cf50aa7bc1ff5a293 refs/heads/prod-readiness-4/2026-08-12
1b352f445bed02398514aba8650257fa884e1d0e refs/heads/prod-readiness-5/2026-08-15
7a3cf54aec2a7e879f2e4f9baa43f887d3d542f9 refs/heads/prod-readiness/2026-08-10
```

`origin/main` is at `cd9778c`: the merge commit `1b352f4` exists only locally and **nothing has been pushed**.
The round-1 through round-4 review trails are inside the merged history and unchanged.

## The standing risk - the `OSLogStore` readers - re-counted at this HEAD

**Ten** tests read `OSLogStore(scope: .currentProcessIdentifier)`: seven in OttoUI, three in OttoPersistence.
Round 4's ledger records "nine at baseline plus a tenth added" (item 5's read, N4-14), and ten is what this count reproduces.

| file | tests that perform a read | line of each read |
|---|---|---|
| `NotificationActionLogTests.swift` | **4** | 58, 91, 153, 180 |
| `SchedulingLogTests.swift` | **2** | 109, 164 |
| `BoundaryLogTests.swift` | **1** | 68 |
| **OttoUI total** | **7** | |
| `CorruptWatermarkTests.swift` | **1** | 57 |
| `UnreportableInvalidationTests.swift` | **1** | 156 |
| `MappingLogPrivacyTests.swift` | **1** | 95 |
| **OttoPersistence total** | **3** | |
| **tree total** | **10** | |

Counted by enumerating the call sites of the four store-opening helpers (`actionLogLines`, `schedulingLogLines`, `boundaryLines`, `OttoLogProbe.persistenceLines`), not by counting files.
`NotificationActionTests.swift` still matches a `grep` for `OSLogStore` and still performs no read; the string is in a doc comment at `:118`.

All ten pass at HEAD inside `verify.sh` and inside all twelve flake runs; no canary assertion fired and no target-line `#require` returned nil.
The risk stays in **CANNOT ASSESS for CI runners**; it is not active on this host.
The standing rule is applied to the real number: **do not add an eleventh**.

## Environments observed

| Dimension | Observed value | Not observed |
|---|---|---|
| Host | macOS 15.6.1 (24G90, Darwin 24.6.0), arm64, Xcode 26.3 (17C529), SwiftLint 0.65.0 | any other toolchain |
| Locale / region | host default, plus `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura` under the harness | every other locale |
| Time zone | America/Toronto | every other zone |
| Runtime | iOS Simulator (iPhone 16 Pro, `<simulator-udid>`) and macOS host | physical device - not used this round-opening |
| Configuration | **Debug** only | **Release - not built or run** |
| Accessibility | no AX client on this host | a host with a usable AX tree |

The 7 known issues are unchanged: all seven are `EmptyStateTests` accessibility-label assertions, standing since `reviews/BASELINE.md`.

## Raw output - `scripts/verify.sh` (exit 0)

```
== VERIFIED: 1b352f445bed02398514aba8650257fa884e1d0e builds, tests, and lints from a clean clone
   OttoDomain: 261
   OttoPersistence: 127
   OttoUI: 209
   total: 597 tests
```

`verify.sh` still prints `docs/next-wave.md` in full as its last act; the banner is elided here, as in every prior baseline, and the elision is marked.
This is the third exit-0 run of `verify.sh` at this tree today; the two earlier runs (during the merge review) returned the same counts.

## Raw output - `swiftlint --strict`, run standalone

```
Done linting! Found 0 violations, 0 serious in 225 files.
```

## Raw output - simulator suite (run from `Packages/OttoUI/`)

```
cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package \
  -destination "id=<simulator-udid>"
```

```
✔ Test run with 119 tests in 22 suites passed after 6.384 seconds.
✔ Test run with 72 tests in 12 suites passed after 0.064 seconds.
✘ Test run with 53 tests in 9 suites passed after 3.087 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Exit 0.
Run from `Packages/OttoUI/`, not the repo root (round 1's RF-4).

## Raw output - the non-Gregorian harness

The command is the one in `CalendarEraTests.swift`'s header, bundle path absolute, run from the repo root (round 3's RF-4 form).
The host suite is now 209 tests, up from 207 at `reviews-4/BASELINE-4.md`, which is round 4's two added OttoUI host tests.

**`th_TH@calendar=buddhist` - 1 issue.**

```
✘ Test run with 209 tests in 38 suites failed after 9.719 seconds with 1 issue.
✘ DisplayFormattingTests.swift:49:9  ("Aug 15, 2569 BE") == "Aug 15, 2026"
```

**`ja_JP@calendar=japanese` - 1 issue.**

```
✘ Test run with 209 tests in 38 suites failed after 7.676 seconds with 1 issue.
✘ DisplayFormattingTests.swift:49:9  ("Aug 15, Reiwa 8") == "Aug 15, 2026"
```

**`ar_SA@calendar=islamic-umalqura` - 5 issues.**

```
✘ Test run with 209 tests in 38 suites failed after 3.401 seconds with 5 issues.
✘ DisplayFormattingTests.swift:49
✘ DisplayFormattingTests.swift:59
✘ DisplayFormattingTests.swift:68
✘ DisplayFormattingTests.swift:69
✘ NotificationReconciliationTests.swift:170
```

These are round 2's **N2-1**, unmoved: the same five citations as every prior baseline.

## Raw output - the flake baseline, twelve full OttoUI runs

`swift test --package-path Packages/OttoUI`, twelve unmutated runs at `1b352f4`.

**The batch ran in two segments.**
Runs 1-3 completed in a first background command; a coordinator status check could not see a live `swift test` process and ordered a restart, at which point the first segment's log showed all three runs already complete.
Runs 4-12 were then taken in a second background command.
No code changed between the segments; both ran the same tree at `1b352f4`.

```
run  1 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.279 seconds.
run  2 rc=0 ✔ Test run with 209 tests in 38 suites passed after 6.127 seconds.
run  3 rc=0 ✔ Test run with 209 tests in 38 suites passed after 5.298 seconds.
run  4 rc=0 ✔ Test run with 209 tests in 38 suites passed after 9.967 seconds.
run  5 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.359 seconds.
run  6 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.461 seconds.
run  7 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.363 seconds.
run  8 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.984 seconds.
run  9 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.669 seconds.
run 10 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.679 seconds.
run 11 rc=0 ✔ Test run with 209 tests in 38 suites passed after 8.387 seconds.
run 12 rc=0 ✔ Test run with 209 tests in 38 suites passed after 7.697 seconds.
```

**12 passed, 0 failed.**

The wall-clock spread in this batch is far below round 4's 15.5-126.4 s band; the daemon was warm from the day's earlier full runs before run 1 started, so this batch does not re-measure N3-8's cold-start cost.
