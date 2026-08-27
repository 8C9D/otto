# Otto

Otto is an iOS subscription and free-trial tracker (SwiftUI, SwiftData, CloudKit private-database sync, no server) that reminds before a renewal or trial conversion and verifies that a cancellation actually stopped the charges.
It never acts for the user: no cancelling, no vendor logins, no payment methods.
Swift 6 with strict concurrency, iOS 26 deployment target, three local SPM packages plus a thin app target.

## Current state

The spec is at **v2.6**, main schema frozen at V3, **640 tests** from `scripts/verify.sh` at `bda8c27` (reconstructed; original stamp predated an amend).
Otto runs on the owner's iPhone with three real subscriptions; CloudKit is still OFF and every store is local.
One wave remains - **6B, CloudKit activation** (`docs/next-wave.md`) - gated on manual procedure 3, the hands-on add-a-subscription pass and the only one of `docs/manual-verification.md`'s four procedures with no row in its run log.
The single sync decision point is `OttoContainerFactory.mainStoreSyncMode`, whose `MainStoreSyncMode` enum has one case (`.off`); 6B replaces that one line, and until it does the kill-switch refusal is a comparison that cannot be true, so it cannot be tested.
`origin/main` is `git@github.com:8C9D/otto.git` and private (spec §10, decision 6).
Where the rest lives: `DECISIONS.md` for what each wave decided, `PROD-READINESS.md` through `PROD-READINESS-5.md` for what each hardening round found and closed, `docs/next-wave.md` for the two gate numberings and what actually gates 6B. This section does not restate them.

## Build and test

The `.xcodeproj` is generated from `project.yml` by XcodeGen and is gitignored, so run `xcodegen generate` after changing `project.yml` and never hand-edit the project file.

Every package tests on the mac host, no simulator involved:

```sh
swift test --package-path Packages/OttoDomain
swift test --package-path Packages/OttoPersistence
swift test --package-path Packages/OttoUI
```

App build:

```sh
xcodebuild build -project Otto.xcodeproj -scheme Otto -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

The OttoUI Dynamic Type suite is UIKit-hosted and compiles to nothing on a mac host, so it runs only on a simulator, and only from `Packages/OttoUI/` rather than the repo root:

```sh
cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination "id=<simulator-udid>"
```

That UDID is the local iPhone 16 Pro simulator, and the run ends `** TEST SUCCEEDED **` with a number of known issues, which is the expected state.

`scripts/verify.sh` is the gate before reporting any wave complete: it clones the committed HEAD into a temp dir, ignoring the working tree, then runs `xcodegen generate`, every package's test suite, the app build, and `swiftlint --strict`, and prints the real per-package test counts.
Report the numbers `verify.sh` prints, never the numbers a working-tree run prints.
Last run at `bda8c27`, 2026-08-21: exit 0, OttoDomain 275, OttoPersistence 130, OttoUI 235, total 640, `swiftlint --strict` clean; the simulator-only Dynamic Type suite is not in that total.
The non-Gregorian harness (a test bundle launched directly under `-AppleLocale th_TH@calendar=buddhist` and two other locales) is documented in the header comment of `Packages/OttoUI/Tests/OttoStoresTests/CalendarEraTests.swift`.

## Key files

- `docs/Subscription-Tracker-Spec.md` is the source of truth for the repo, with the main synced schema frozen at V3; `e869f99` reconciled its once-stale spots, so its top status line (v2.6, 640 tests), the wave table in §8, and the §9a known-issues table are all current — read §8 for what is done.
- `DECISIONS.md` records the calls a wave made where the spec left room.
- `PROD-READINESS.md` through `PROD-READINESS-5.md` are the prod-readiness ledgers, with the matching baselines and adversarial reviews in `reviews/` through `reviews-5/`.
- `.claude/commands/round5.md` describes how a prod-readiness round is run.
- `docs/next-wave.md` names the next wave and carries the user-facing note on repairing a non-Gregorian device's corrupted dates.
- `docs/cloudkit-readiness.md` is the Wave 6A audit of what breaks under sync and ends with the pre-6B work list; `docs/manual-verification.md` holds the four device-gate procedures and the dated run log; `docs/sync-safety.md` covers the §4a sync mechanisms plus, in its "Wall-clock timestamps are a merge input" section, the clock-monotonicity defect and the fix now implemented.
- `docs/implementation-notes/wave-*.md` are the per-wave notes.

## Conventions

The layering is one-way and compiler-enforced (spec §3.4): UI to services to repository protocols to persistence adapters to domain.
`Packages/OttoDomain` imports nothing but Foundation, and the app target is the only target that links concrete `OttoPersistence`.
In the domain, money is integer cents, billing dates are `CalendarDay` values and never `Date`, and "today" is always a parameter rather than a clock read.

`PRODUCT_BUNDLE_IDENTIFIER` is `com.arthurzhang.otto` and is permanent (spec §10, decision 1).

Updating `docs/next-wave.md` is part of landing a wave, and `verify.sh` fails if that file is missing or empty.

CI, not `verify.sh`, is the real gate, because `verify.sh` reruns the same locale on the same hardware and cannot see a host-environment dependency; note that `.claude/commands/round5.md` records GitHub Actions as dead on a billing limit, so every recent measurement comes from the one host.

In a prod-readiness round the work list is frozen at opening, every item must reach RESOLVED, DEFERRED, or REJECTED TWICE, every commit sits inside a declared review range, and new P3 findings go to NEXT ROUND with their measurements instead of being fixed.

Standing rules from those rounds: do not add an eleventh `OSLogStore` reader, no new dependency, package, or target without an explicit user decision, and stochastic claims need repeated runs rather than one sample.
