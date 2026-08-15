# BASELINE-3 - Otto production-readiness, round 3

Captured 2026-08-11 against commit `8806853a2df273175b82581eaa151a67cc58fbcd` (branch `prod-readiness-3/2026-08-11`, created from `prod-readiness-2/2026-08-10` at its HEAD).

Working tree was clean at preflight (`git status --porcelain` empty).
No commits precede this file on the branch.

## Result: all three baselines reproduce exactly. No pre-existing failure moved.

| measurement | round-3 prompt predicted | re-derived here at `8806853` | result |
|---|---|---|---|
| `scripts/verify.sh` | exit 0, 565 tests (OttoDomain 251, OttoPersistence 118, OttoUI 196) | **exit 0**; OttoDomain **251**, OttoPersistence **118**, OttoUI **196**, total **565** | ✅ exact |
| `swiftlint --strict` | clean | clean (inside `verify.sh`) | ✅ |
| simulator suite | `** TEST SUCCEEDED **`, 108 / 70 / 31, 7 known issues | exit 0, `** TEST SUCCEEDED **`, **108 / 70 / 31**, `with 7 known issues` | ✅ exact |
| non-Gregorian harness | 1 / 1 / 5 issues | **1 / 1 / 5** | ✅ exact |

Every later "nothing worse than baseline" claim in this run is measured against: **565 host tests, lint clean under `--strict`, simulator 108 / 70 / 31 with 7 known issues, non-Gregorian 1 / 1 / 5.**

`8806853` is documentation-only relative to `aa92ca7` and `3ce3e01`, where round 2 measured these numbers.
That was verified rather than assumed: the three commands were re-run here, from the committed state, and produced the predicted numbers.

## Provenance, established without a network call

`git ls-remote`, `git fetch` and `git pull` are prohibited this run; everything below is from `git show-ref`, `refs/remotes/` and `git branch -a --contains`.

```
406a5a686d1c6b67d251ba38c36545ebbb772ff3 refs/heads/main
7a3cf54aec2a7e879f2e4f9baa43f887d3d542f9 refs/heads/prod-readiness/2026-08-10
8806853a2df273175b82581eaa151a67cc58fbcd refs/heads/prod-readiness-2/2026-08-10
8806853a2df273175b82581eaa151a67cc58fbcd refs/heads/prod-readiness-3/2026-08-11
406a5a686d1c6b67d251ba38c36545ebbb772ff3 refs/remotes/origin/main
```

`git merge-base main HEAD` gives `406a5a6`, and `git log --oneline main..HEAD | wc -l` gives **48**.
So `origin/main` is still at `406a5a6`: **nothing from round 1 or round 2 has been merged or pushed**, exactly as the prompt states.

## The four `OSLogStore` tests - the standing risk, checked before anything else

Round 2 introduced four tests that read `OSLogStore(scope: .currentProcessIdentifier)` and carried them into CI on runners nobody has exercised.
The prompt requires establishing which state they are in *before* changing anything.

**All four pass at HEAD.**
Run individually, on the host:

```
✔ Test "⛔ a snooze that threw leaves a FAILED line naming the action, the rung and the error type" passed after 11.602 seconds.
✔ Test "a successful action is recorded too, so silence in the log means the handler never ran" passed after 11.602 seconds.
✔ Test "⛔ the reconcile line the scheduler actually emits names a reason per failed rung" passed after 11.602 seconds.
✔ Test run with 5 tests in 2 suites passed after 11.602 seconds.

✔ Test "⛔ the line the store actually emits carries the field and NOT the value" passed after 10.556 seconds.
✔ Test run with 3 tests in 2 suites passed after 10.557 seconds.
```

Neither failure cause is present: no `requireDelivered` canary assertion fired, so the log daemon is delivering, and no target-line `#require` returned nil, so the production log statements are intact.
The risk stays in CANNOT ASSESS for CI runners; it is not active here.

The cost round 2 recorded is confirmed: the two suites take ~11 s each because of the log reads.
That is deliberate and is not a defect.

## Environments observed - unchanged from round 2

| Dimension | Observed value | Not observed |
|---|---|---|
| Host | macOS 15.6.1 (Darwin 24.6.0), arm64, Xcode 26.3 (17C529), SwiftLint 0.65.0 | any other toolchain |
| Locale / region | host default `en_CA`, plus `th_TH@calendar=buddhist`, `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura` under the harness | every other locale |
| Device calendar | Gregorian (host default), plus Buddhist, Japanese and Islamic-umalqura in a real host test process | Hebrew, ROC, Persian |
| Time zone | America/Toronto | every other zone |
| Runtime | iOS **Simulator** (iPhone 16 Pro, `<simulator-udid>`, iOS 26.3) and macOS host | **physical device - prohibited this run** |
| Configuration | **Debug** only | **Release - not built or run this run** |
| Accessibility | **no AX client on this host** | a host with a usable AX tree |

## The 7 known issues are unchanged

All seven are `EmptyStateTests` accessibility-label assertions.
This host vends no accessibility tree.
Unchanged from `reviews/BASELINE.md` and `reviews-2/BASELINE-2.md`; not a regression and not clean either.

## Contamination

`scripts/verify.sh` still prints `docs/next-wave.md` in full as its last act, so its raw output carries round 1's disclosed defect list and the Gate 3 procedure.
**This does not contaminate round 3**: this run works from a frozen list handed to it in the prompt and makes no discovery claim of any kind.
The banner is elided below where it repeats `reviews-2/BASELINE-2.md` verbatim, and the elision is marked.

## Raw output - `scripts/verify.sh` (exit 0)

```
== Otto verify: committed HEAD 8806853a2df273175b82581eaa151a67cc58fbcd
== Working tree state is deliberately ignored; only the clone is tested.
== packages (derived from the clone's Packages/): OttoDomain OttoPersistence OttoUI
== xcodegen generate
== swift test: OttoDomain
== swift test: OttoPersistence
== swift test: OttoUI
== xcodebuild: app target (simulator, unsigned)
== swiftlint --strict

== VERIFIED: 8806853a2df273175b82581eaa151a67cc58fbcd builds, tests, and lints from a clean clone
   OttoDomain: 251
   OttoPersistence: 118
   OttoUI: 196
   total: 565 tests

   NOT counted: the OttoUI Dynamic Type suite is UIKit-hosted and compiles
   to nothing under swift test on a mac host. It runs only on a simulator
   (the CI simulator job, or xcodebuild test locally) - do not report its
   tests as covered by this script's total.

== NEXT WAVE (docs/next-wave.md - update it as part of landing a wave):
   [elided - byte-identical to the banner reproduced in full in reviews-2/BASELINE-2.md,
    which is round 2's record and is not edited by this run]
```

## Raw output - simulator suite (tail; run from `Packages/OttoUI/`)

```
cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package \
  -destination "id=<simulator-udid>"
```

```
✔ Test run with 108 tests in 20 suites passed after 4.254 seconds.
✔ Test run with 70 tests in 12 suites passed after 0.203 seconds.
✘ Test run with 31 tests in 6 suites passed after 3.665 seconds with 7 known issues.
** TEST SUCCEEDED **
```

Exit 0.
The command must be run from `Packages/OttoUI/`, not the repo root - from the root the generated `Otto.xcodeproj` shadows the package and `xcodebuild` exits 65 (round 1's RF-4).

## Raw output - the non-Gregorian harness

The command is the one in `CalendarEraTests.swift`'s header:

```
swift build --build-tests --package-path Packages/OttoUI
HELPER="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
BUNDLE="Packages/OttoUI/.build/arm64-apple-macosx/debug/OttoUIPackageTests.xctest/Contents/MacOS/OttoUIPackageTests"
export DYLD_FRAMEWORK_PATH="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
"$HELPER" --test-bundle-path "$BUNDLE" "$BUNDLE" --testing-library swift-testing -AppleLocale "$LOCALE"
```

**`th_TH@calendar=buddhist` - 1 issue.**

```
✘ Test run with 196 tests in 36 suites failed after 12.217 seconds with 1 issue.
✘ Test "calendar days render through the locale, never by interpolation" recorded an issue at
  DisplayFormattingTests.swift:49:9: Expectation failed:
  (day.displayText(calendar: Calendar(identifier: .gregorian), locale: enCA) → "Aug 15, 2569 BE") == "Aug 15, 2026"
```

**`ja_JP@calendar=japanese` - 1 issue.**

```
✘ Test run with 196 tests in 36 suites failed after 6.740 seconds with 1 issue.
✘ Test "calendar days render through the locale, never by interpolation" recorded an issue at
  DisplayFormattingTests.swift:49:9: Expectation failed:
  (day.displayText(calendar: Calendar(identifier: .gregorian), locale: enCA) → "Aug 15, Reiwa 8") == "Aug 15, 2026"
```

**`ar_SA@calendar=islamic-umalqura` - 5 issues.**

```
✘ Test run with 196 tests in 36 suites failed after 10.565 seconds with 5 issues.
✘ DisplayFormattingTests.swift:49:9  ("Rab. I 2, 1448 AH") == "Aug 15, 2026"
✘ DisplayFormattingTests.swift:59:9  (cycleText(every45) → "Every ٤٥ days") == "Every 45 days"
✘ DisplayFormattingTests.swift:68:9  (subscriptionCountText(1) → "١ subscription") == "1 subscription"
✘ DisplayFormattingTests.swift:69:9  (subscriptionCountText(3) → "٣ subscriptions") == "3 subscriptions"
✘ NotificationReconciliationTests.swift:170:9
  (renewal.body → "FoodApp charges $15.99 on Rab. I 12.") == "FoodApp charges $15.99 on Aug 25."
```

These are round 2's **N2-1**, and the failing tests are exactly the ones its ledger and `CalendarEraTests.swift` name.
That includes the split between the two calendar-caused failures (`:49` on any non-Gregorian host, `:170` only where the month disagrees) and the three numbering-system-caused ones under `ar_SA` alone.
Every F1 guard passes in all three runs.
