# Wave 0 - project scaffold

Date: 2026-08-06

## What exists after this wave

- XcodeGen project definition in `project.yml`; the `.xcodeproj`, `Info.plist`, and entitlements file are all generated from it and gitignored.
- iOS app target `Otto`, bundle ID `com.arthurzhang.otto` (permanent), display name Otto, deployment target iOS 26.0.
- Swift 6 language mode with strict concurrency set to complete, both in the app target and in the `OttoDomain` package.
- Entitlements configured ahead of use per the Wave 0 gate: iCloud (CloudKit) with container `iCloud.com.arthurzhang.otto`, background modes (fetch + remote notifications), and time-sensitive notifications.
- Folder structure enforcing the spec §3.4 layering: `Packages/OttoDomain` (Wave 1), `Otto/Persistence` (Wave 2), `Otto/Features` (Wave 3+), `Otto/Services` (Wave 4+), `Otto/App`.
- `Packages/OttoDomain` builds and tests via `swift test` with a placeholder source file and a trivial test, satisfying the "empty test suite runs" gate.
- SwiftLint with force-unwrap, force-try, and force-cast as errors.
- GitHub Actions CI with two jobs: domain tests via `swift test`, and app build plus `swiftlint --strict` on a macOS 26 runner.

## Decisions worth recording

- The generated `Info.plist` and `.entitlements` are treated exactly like the `.xcodeproj`: outputs of `project.yml`, never hand-edited, never committed.
- `aps-environment: development` is included because CloudKit sync (Wave 6) delivers changes via silent remote notifications; automatic signing will manage the production value at archive time.
- The time-sensitive notifications entitlement may need the capability enabled on the App ID in the developer portal before device builds sign; simulator builds are unaffected.
- No app-level test target exists yet; all Wave 1 tests live in the package, which is the point of the package boundary.
