# Otto

Otto is a subscription and free-trial tracker for iOS. It reminds you before a
subscription renews or a free trial converts to paid, and it verifies that a
subscription you cancelled actually stopped charging you.

Otto never acts on your behalf: it never cancels anything, never logs in to a
vendor, and never touches a payment method. It reminds, records, and verifies.

Swift 6 across three local Swift packages and a thin app target, with a
host-run test suite of 640 cases. CloudKit sync is designed in and switched
off.

## Why it exists

Two failures every subscription tracker should prevent and almost none do:

- **The silent trial conversion.** A free trial converts to paid, nobody
  notices, and a service that was never used is billed for months.
- **The cancellation that didn't take.** A subscription is cancelled, the
  cancellation is confirmed, and the charges keep arriving.

The first is a forward-looking reminder problem. The second is a
backward-looking verification problem, and it is the one Otto is built
around: a subscription's lifecycle does not end when you cancel it, it ends
when you have confirmed the money stopped moving. Cancelling a subscription
in Otto opens a **cancellation episode** that schedules a check on the next
expected charge date and asks whether the charge arrived, and the episode
stays open until you say it did not.

## What it does

- Tracks subscriptions and free trials with billing cycle, trial term,
  next-charge date, category, payment method and price history.
- Schedules local reminders ahead of every renewal and trial conversion,
  within iOS's 64 pending-notification budget, and re-plans them whenever
  the data changes.
- Verifies cancellations and pauses with follow-up prompts on the dates a
  charge would have landed.
- Insights: monthly burn, per-payment-method totals, and a "zombie" report of
  subscriptions you pay for but have not used.
- Export and import of the whole dataset as versioned JSON, plus a charges
  CSV, so the data is never trapped in the app.

## Architecture

```
Otto (app target)          composition root; the only target that links
                           the concrete persistence adapter
  └─ OttoUI (package)
       ├─ OttoUI           SwiftUI views
       ├─ OttoStores       observable view models, load states
       └─ OttoServices     notification scheduling, export, flows
            └─ OttoRepositories (protocols)      ─┐
                                                  │ OttoPersistence (package)
  OttoPersistence                                 │ SwiftData schema V1→V3,
       SwiftData adapters, migrations, watermarks ┘ store, mapping
            └─ OttoDomain (package)
                 pure value types and functions: money in integer cents,
                 dates as CalendarDay, "today" always a parameter
```

The layering is one-way and compiler-enforced, not a convention. Each layer
lives in its own package or module, so UI code cannot import the persistence
adapter and the domain cannot import SwiftData, SwiftUI or UserNotifications.

**The domain is pure.** Every billing-date calculation, reminder plan,
verification schedule and insight is a function of explicit inputs. Money is
integer cents. Billing dates are `CalendarDay` values, never `Date`, so a
device set to the Buddhist or Japanese calendar computes the same renewal day
as one set to Gregorian. "Today" is always passed in, never read from a
clock, which is what makes the scheduling logic testable to the day.

**Persistence is versioned and migrated.** The SwiftData schema is frozen at
V3 with an explicit migration plan from V1. Export and import share a
versioned wire format, and importing into an existing store is a merge that
reconstructs notification watermarks from the billing ledger rather than
trusting the file.

**Notifications are planned, then reconciled.** The scheduler computes the
full set of reminders the data implies, diffs it against what iOS reports as
pending, and applies only the difference. A coalescing layer makes sure two
edits in quick succession produce one pass, and a coverage-gap card in the
UI says out loud when the 64-slot budget cannot cover every reminder.

## Stack

| | |
| --- | --- |
| Language | Swift 6, strict concurrency `complete`, iOS 26 deployment target |
| UI | SwiftUI, Dynamic Type verified at every size class |
| Data | SwiftData, versioned schema with migrations; CloudKit private-database sync designed in and currently off |
| Notifications | UserNotifications, planned and reconciled on-device; no server |
| Project | XcodeGen (`project.yml`), three local Swift packages |
| Tests | Swift Testing, 640 cases across the three packages plus a simulator-only Dynamic Type suite |
| Tooling | SwiftLint `--strict`, `scripts/verify.sh` clean-clone gate, GitHub Actions |

## Build and run

Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The
`.xcodeproj` is generated from `project.yml` and is not committed.

```sh
brew install xcodegen swiftlint
xcodegen generate
open Otto.xcodeproj          # run the Otto scheme on a simulator or device
```

### Tests

Each package tests on the Mac host, with no Xcode project and no simulator:

```sh
swift test --package-path Packages/OttoDomain
swift test --package-path Packages/OttoPersistence
swift test --package-path Packages/OttoUI
```

The OttoUI Dynamic Type suite is UIKit-hosted and compiles to nothing on the
host; it runs on a simulator:

```sh
cd Packages/OttoUI
xcodebuild test -scheme OttoUI-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### The verification gate

```sh
scripts/verify.sh
```

Clones the committed `HEAD` into a temp directory, deliberately ignoring the
working tree, then generates the project, runs every package's tests, builds
the app target and lints under `--strict`. It exists because a committed
revision once failed to compile while the working tree passed; a green local
run is not evidence about the artifact.

## Repository map

```
Otto/               app target: entry point, assets, generated Info.plist
Packages/
  OttoDomain/       pure domain: models, date engine, scheduling, insights, export format
  OttoPersistence/  SwiftData schema + migrations, store, repository protocols
  OttoUI/           views, stores, services (notifications, export, flows)
docs/
  Subscription-Tracker-Spec.md   the product and technical spec, source of truth
  sync-safety.md, cloudkit-readiness.md   what has to hold before sync turns on
DECISIONS.md        calls made during implementation where the spec left room
scripts/            verify.sh, app-icon generator, export options
```
