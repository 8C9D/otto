# Otto

Otto is a subscription and free-trial tracker for iOS.
It reminds you before a subscription renews or a free trial converts to paid, and it verifies that a subscription you cancelled actually stopped charging you.
Otto never acts on your behalf: it never cancels anything, never logs in to a vendor, and never touches a payment method.
It reminds, records, and verifies.

The full product and technical spec lives at `docs/Subscription-Tracker-Spec.md` and is the source of truth for this repo.

## The layering rule

The codebase follows a strict one-way layering (spec §3.4): UI → services → repository protocols → persistence adapters → domain.
The domain layer at `Packages/OttoDomain` is a standalone Swift package that imports nothing but Foundation - no SwiftData, no SwiftUI, no UserNotifications, no third-party packages.
It lives in its own package specifically so the compiler enforces that rule rather than discipline.
Everything in the domain is a pure value type or a pure function: money is integer cents, billing dates are `CalendarDay` values (never `Date`), and "today" is always a parameter, never a clock read.

## Running the tests

Each package tests on a mac host with no Xcode project and no simulator:

```sh
swift test --package-path Packages/OttoDomain
swift test --package-path Packages/OttoPersistence
swift test --package-path Packages/OttoUI
```

The one exception is the OttoUI Dynamic Type suite, which is UIKit-hosted and compiles to nothing on a mac host; it runs on a simulator via the CI job or `xcodebuild test`.

## Verifying a wave

Before reporting any wave complete, run:

```sh
scripts/verify.sh
```

It clones the committed HEAD into a temp directory - deliberately ignoring the working tree - then generates the project, runs every package's tests, builds the app target, and lints under `--strict`, failing loudly on any error and printing the real per-package test counts.
It exists because Wave 4's committed HEAD did not compile while the local tree passed: a green local run is not evidence about the artifact.
Report the numbers verify.sh prints, not the numbers a working-tree run prints.

Every run ends by printing `docs/next-wave.md` - a one-line pointer naming the next wave and where it is specified - and fails if that file is missing or empty.
Updating that line is part of landing a wave: the closing session points it at whatever comes next.
The banner deliberately claims nothing about whether any wave was actually done; the script cannot know that, and a checklist that lies is worse than none.

## Building the app

The `.xcodeproj` is generated from `project.yml` and is not committed:

```sh
xcodegen generate
open Otto.xcodeproj
```
