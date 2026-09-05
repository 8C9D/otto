# Otto

Otto is an iOS subscription and free-trial tracker (SwiftUI, SwiftData, CloudKit private-database sync designed in and switched off, no server) that reminds before a renewal or trial conversion and verifies that a cancellation actually stopped the charges.
It never acts for the user: no cancelling, no vendor logins, no payment methods.
Swift 6 with strict concurrency, iOS 26 deployment target, three local SPM packages plus a thin app target.

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
cd Packages/OttoUI && xcodebuild test -scheme OttoUI-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

The run ends `** TEST SUCCEEDED **` with a number of known issues, which is the expected state.

`scripts/verify.sh` is the gate before reporting any change complete: it clones the committed HEAD into a temp dir, ignoring the working tree, then runs `xcodegen generate`, every package's test suite, the app build, and `swiftlint --strict`, and prints the real per-package test counts.
Report the numbers `verify.sh` prints, never the numbers a working-tree run prints.
The non-Gregorian harness (a test bundle launched directly under `-AppleLocale th_TH@calendar=buddhist` and two other locales) is documented in the header comment of `Packages/OttoUI/Tests/OttoStoresTests/CalendarEraTests.swift`.

## Key files

- `docs/Subscription-Tracker-Spec.md` is the source of truth for the repo, with the main synced schema frozen at V3; read §8 for what is done.
- `DECISIONS.md` records the calls a wave made where the spec left room.
- `docs/cloudkit-readiness.md` is the audit of what breaks under sync and ends with the pre-sync work list; `docs/sync-safety.md` covers the sync mechanisms built before CloudKit can be enabled, including the clock-monotonicity defect and its fix.

## Conventions

The layering is one-way and compiler-enforced (spec §3.4): UI to services to repository protocols to persistence adapters to domain.
`Packages/OttoDomain` imports nothing but Foundation, and the app target is the only target that links concrete `OttoPersistence`.
In the domain, money is integer cents, billing dates are `CalendarDay` values and never `Date`, and "today" is always a parameter rather than a clock read.

`PRODUCT_BUNDLE_IDENTIFIER` is `com.arthurzhang.otto` and is permanent (spec §10, decision 1).

Standing rules: do not add an eleventh `OSLogStore` reader, no new dependency, package, or target without an explicit user decision, and stochastic claims need repeated runs rather than one sample.
