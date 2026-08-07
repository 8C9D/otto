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

The domain tests need no Xcode project and no simulator:

```sh
swift test --package-path Packages/OttoDomain
```

## Building the app

The `.xcodeproj` is generated from `project.yml` and is not committed:

```sh
xcodegen generate
open Otto.xcodeproj
```
