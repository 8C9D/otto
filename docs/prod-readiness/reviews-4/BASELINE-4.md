# BASELINE-4 - Otto production-readiness, round 4

Captured 2026-08-12 against commit `2d8913c4a80566347dcb067b0e261d3dc4342b05` (branch `prod-readiness-4/2026-08-12`, created from `prod-readiness-3/2026-08-11` at its HEAD).

Working tree was clean at preflight (`git status --porcelain` empty), and no commit precedes this file on the branch.

## Result: all four prior baselines reproduce exactly, and the fifth dimension is established

| measurement | round-4 prompt predicted | re-derived here at `2d8913c` | result |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 589 tests (OttoDomain 258, OttoPersistence 124, OttoUI 207) | **exit 0**; OttoDomain **258**, OttoPersistence **124**, OttoUI **207**, total **589** | ✅ exact |
| `swiftlint --strict` | clean | `Found 0 violations, 0 serious in 220 files` | ✅ |
| simulator suite | `** TEST SUCCEEDED **`, 117 / 72 / 36, 7 known issues | exit 0, `** TEST SUCCEEDED **`, **117 / 72 / 36**, `with 7 known issues` | ✅ exact |
| non-Gregorian harness | 1 / 1 / 5 issues | **1 / 1 / 5**, same five citations | ✅ exact |
| **flake rate (new)** | not predicted - this run establishes it | **12 of 12 passed, 0 failed** | established |

Every later "nothing worse than baseline" claim in this run is measured against: **589 host tests, lint clean under `--strict`, simulator 117 / 72 / 36 with 7 known issues, non-Gregorian 1 / 1 / 5, and 12 of 12 clean full OttoUI runs.**

## Provenance, established without a network call

`git ls-remote`, `git fetch` and `git pull` are prohibited this run; everything below is from `git show-ref`, `refs/remotes/` and `git log`.

```
406a5a686d1c6b67d251ba38c36545ebbb772ff3 refs/heads/main
8806853a2df273175b82581eaa151a67cc58fbcd refs/heads/prod-readiness-2/2026-08-10
2d8913c4a80566347dcb067b0e261d3dc4342b05 refs/heads/prod-readiness-3/2026-08-11
2d8913c4a80566347dcb067b0e261d3dc4342b05 refs/heads/prod-readiness-4/2026-08-12
7a3cf54aec2a7e879f2e4f9baa43f887d3d542f9 refs/heads/prod-readiness/2026-08-10
406a5a686d1c6b67d251ba38c36545ebbb772ff3 refs/remotes/origin/main
```

`git merge-base main HEAD` gives `406a5a6`, and `git log --oneline main..HEAD | wc -l` gives **69**.
So `origin/main` is still at `406a5a6`: **nothing from rounds 1, 2 or 3 has been merged or pushed**, exactly as the prompt states.
`.git/FETCH_HEAD` does not exist.

## The standing risk - the `OSLogStore` readers - checked before any edit

**Nine** tests read `OSLogStore(scope: .currentProcessIdentifier)`: seven in OttoUI, two in OttoPersistence.
The prompt says six; that count is measured and corrected in the next section.

**All of them pass at HEAD**, inside the full `verify.sh` run and inside all twelve flake runs.
No `requireDelivered` canary assertion fired, so the log daemon is delivering on this host, and no target-line `#require` returned nil, so the production log statements are intact.

`MappingLogPrivacyTests` is the exception the prompt names as item 6: it has **no canary**, so "no canary assertion fired" is vacuously true of it, and on a runner where the store is readable but empty it would fail at `#expect(!ours.isEmpty, ...)` - byte-identical to the regression signature the canary exists to disambiguate. That is the state to change, not a failure at HEAD.

The risk stays in CANNOT ASSESS for CI runners; it is not active here.

## The reader count, measured rather than inherited - and it is not six

The prompt says "There are six." `reviews-3/REVIEW-5.md` Explicit check 6 says "the count stays at six in OttoUI and one in OttoPersistence".
Both are wrong. Counted at `2d8913c` by enumerating the call sites of every helper that opens a store, not by counting files:

| file | tests that perform a read | line of each read |
|---|---|---|
| `NotificationActionLogTests.swift` | **4** | 58, 91, 153, 180 |
| `SchedulingLogTests.swift` | **2** | 66, 115 |
| `BoundaryLogTests.swift` | **1** | 68 |
| **OttoUI total** | **7** | |
| `CorruptWatermarkTests.swift` | **1** | 57 |
| `MappingLogPrivacyTests.swift` | **1** | 85 (no canary - item 6) |
| **OttoPersistence total** | **2** | |
| **tree total** | **9** | |

`NotificationActionTests.swift` matches a `grep` for `OSLogStore` and performs **no** read: the string is in a doc comment at `:118-121` explaining what that test does *not* do.
That is how a file-level count reaches six: four files that read, plus two shared probes, minus the comment-only match, all counted as files rather than as reads.

The number that matters for the standing risk is the number of tests that block on the daemon, and that is **nine**, seven of them in the suite whose wall time this run measures twelve times.
Recorded here so no later count in this run has to be reconciled against a figure that was scoped differently, and so the "do not add a seventh" rule in the prompt is applied to the real number.

## Environments observed - unchanged from round 3

| Dimension | Observed value | Not observed |
|---|---|---|
| Host | macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3, SwiftLint 0.65.0 | any other toolchain |
| Locale / region | host default, plus `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura` under the harness | every other locale |
| Device calendar | Gregorian (host default), plus Buddhist, Japanese and Islamic-umalqura in a real host test process | Ethiopic, Indian, Hebrew, ROC, Persian |
| Time zone | America/Toronto | every other zone |
| Runtime | iOS **Simulator** (iPhone 16 Pro, `<simulator-udid>`) and macOS host | **physical device - prohibited this run** |
| Configuration | **Debug** only | **Release - not built or run this run** |
| Accessibility | **no AX client on this host** | a host with a usable AX tree |

## The 7 known issues are unchanged

All seven are `EmptyStateTests` accessibility-label assertions.
This host vends no accessibility tree.
Unchanged from `reviews/BASELINE.md`, `reviews-2/BASELINE-2.md` and `reviews-3/BASELINE-3.md`; not a regression and not clean either.

## Raw output - `scripts/verify.sh` (exit 0)

```
== Otto verify: committed HEAD 2d8913c4a80566347dcb067b0e261d3dc4342b05
== Working tree state is deliberately ignored; only the clone is tested.
== packages (derived from the clone's Packages/): OttoDomain OttoPersistence OttoUI
== xcodegen generate
== swift test: OttoDomain
== swift test: OttoPersistence
== swift test: OttoUI
== xcodebuild: app target (simulator, unsigned)
== swiftlint --strict

== VERIFIED: 2d8913c4a80566347dcb067b0e261d3dc4342b05 builds, tests, and lints from a clean clone
   OttoDomain: 258
   OttoPersistence: 124
   OttoUI: 207
   total: 589 tests
```

`verify.sh` still prints `docs/next-wave.md` in full as its last act; the banner is elided here, as in rounds 2 and 3, and the elision is marked.

## Raw output - `swiftlint --strict`, run standalone

```
Done linting! Found 0 violations, 0 serious in 220 files.
```

## Raw output - simulator suite (run from `Packages/OttoUI/`)

```
cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package \
  -destination "id=<simulator-udid>"
```

```
✔ Test run with 117 tests in 22 suites passed after 6.748 seconds.
✔ Test run with 72 tests in 12 suites passed after 0.135 seconds.
✘ Test run with 36 tests in 7 suites passed after 3.215 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Exit 0.
The command must be run from `Packages/OttoUI/`, not the repo root - from the root the generated `Otto.xcodeproj` shadows the package and `xcodebuild` exits 65 (round 1's RF-4).

## Raw output - the non-Gregorian harness

The command is the one in `CalendarEraTests.swift`'s header, with the bundle path **absolute** and run from the repo root (round 3's RF-4 addition):

```
swift build --build-tests --package-path Packages/OttoUI
HELPER="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
BUNDLE="/Users/<user>/dev/otto/Packages/OttoUI/.build/arm64-apple-macosx/debug/OttoUIPackageTests.xctest/Contents/MacOS/OttoUIPackageTests"
export DYLD_FRAMEWORK_PATH="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
"$HELPER" --test-bundle-path "$BUNDLE" "$BUNDLE" --testing-library swift-testing -AppleLocale "$LOCALE"
```

**`th_TH@calendar=buddhist` - 1 issue.**

```
✘ Test run with 207 tests in 38 suites failed after 56.061 seconds with 1 issue.
✘ DisplayFormattingTests.swift:49:9  ("Aug 15, 2569 BE") == "Aug 15, 2026"
```

**`ja_JP@calendar=japanese` - 1 issue.**

```
✘ Test run with 207 tests in 38 suites failed after 45.431 seconds with 1 issue.
✘ DisplayFormattingTests.swift:49:9  ("Aug 15, Reiwa 8") == "Aug 15, 2026"
```

**`ar_SA@calendar=islamic-umalqura` - 5 issues.**

```
✘ Test run with 207 tests in 38 suites failed after 62.172 seconds with 5 issues.
✘ DisplayFormattingTests.swift:49:9   ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
✘ DisplayFormattingTests.swift:59:9   ("Every ٤٥ days") == "Every 45 days"
✘ DisplayFormattingTests.swift:68:9   ("١ subscription") == "1 subscription"
✘ DisplayFormattingTests.swift:69:9   ("٣ subscriptions") == "3 subscriptions"
✘ NotificationReconciliationTests.swift:170:9
    ("FoodApp charges $15.99 on Rab. I 12.") == "FoodApp charges $15.99 on Aug 25."
```

These are round 2's **N2-1**, unmoved: the same five citations, the same split between the two calendar-caused failures (`:49` on any non-Gregorian host, `:170` only where the month disagrees) and the three numbering-system-caused ones under `ar_SA` alone.
Every F1 guard passes in all three runs.

## Raw output - the flake baseline, twelve full OttoUI runs

`swift test --package-path Packages/OttoUI`, twelve consecutive unmutated runs at `2d8913c`.
This dimension is new in round 4 because round 3 shipped a test that failed 3 runs in 12 and passed every gate its prompt specified.

```
run  1 rc=0 ✔ Test run with 207 tests in 38 suites passed after 105.985 seconds.
run  2 rc=0 ✔ Test run with 207 tests in 38 suites passed after 100.229 seconds.
run  3 rc=0 ✔ Test run with 207 tests in 38 suites passed after 126.389 seconds.
run  4 rc=0 ✔ Test run with 207 tests in 38 suites passed after 109.760 seconds.
run  5 rc=0 ✔ Test run with 207 tests in 38 suites passed after  42.856 seconds.
run  6 rc=0 ✔ Test run with 207 tests in 38 suites passed after  39.732 seconds.
run  7 rc=0 ✔ Test run with 207 tests in 38 suites passed after  32.176 seconds.
run  8 rc=0 ✔ Test run with 207 tests in 38 suites passed after  36.484 seconds.
run  9 rc=0 ✔ Test run with 207 tests in 38 suites passed after  37.222 seconds.
run 10 rc=0 ✔ Test run with 207 tests in 38 suites passed after  17.627 seconds.
run 11 rc=0 ✔ Test run with 207 tests in 38 suites passed after  15.450 seconds.
run 12 rc=0 ✔ Test run with 207 tests in 38 suites passed after  25.135 seconds.
SUMMARY pass=12 fail=0
```

**12 passed, 0 failed.**

Twelve runs cannot prove a 0 % rate; they are the sample size that measured round 3's 25 % defect, and they are the sample size every stage of this run is measured against.

**The wall-clock spread is the standing `OSLogStore` cost, and it is large.**
The same 207-test suite ran in **15.5 s and 126.4 s** in this one batch - an 8.2x spread with no code change - because the nine log-reading tests run in parallel and all block on the same daemon.
The batch is also strongly ordered: the first four runs average 110 s and the last four average 24 s, which is the daemon warming rather than anything about the code.
That is `PROD-READINESS-3.md` N3-8, re-measured, and it is a reason not to add an eighth reader rather than a defect in itself.

## One commit outside every review range ever issued, inherited by this run

`reviews-3/REVIEW-1.md` finding 4 and `PROD-READINESS-3.md` N3-4 record it; re-derived here rather than taken on their word:

```
$ git log --oneline 3ce3e01..8806853
8806853 Close the stage-6 review range and stamp the HEAD verification   (documents)
aa92ca7 Give the failure list its own log entry, and make an empty log diagnosable   (CODE)
70f3f19 Add the adversarial review of stage 6                            (documents)

$ git show --stat --name-only aa92ca7 | tail -6
PROD-READINESS-2.md
Packages/OttoUI/Sources/OttoServices/NotificationScheduler+Reconcile.swift
Packages/OttoUI/Sources/OttoServices/NotificationScheduler.swift
Packages/OttoUI/Tests/OttoServicesTests/NotificationActionLogTests.swift
Packages/OttoUI/Tests/OttoServicesTests/OttoLogProbe.swift
Packages/OttoUI/Tests/OttoServicesTests/SchedulingLogTests.swift
```

Round 2's last review covered `5d8ed6a..3ce3e01`; round 3's first range started at `8806853` because its prompt fixed that as the starting point.
`aa92ca7` therefore falls between two reviewed ranges and its **diff has been read by no reviewer in three rounds**, while its *effect* is inside every baseline measured since.
Closing it is item 6 of this run.
