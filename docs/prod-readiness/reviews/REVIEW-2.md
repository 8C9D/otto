# REVIEW-2 — pass 2 (F1, date/calendar), commit range `3925084..75a8b31`

**VERDICT: REJECT**

The storage-and-display half of F1 is genuinely fixed, correctly, at the four sites the ledger names.
The stage is rejected for one reason: on the devices F1 is about, the committed change moves the app from *delivering reminders* to *never delivering them*, because the day numbers are resolved a second time - by iOS, in the device calendar - at a fifth conversion site the fix does not touch.
That is the app's characteristic failure ("silence on a phone in a drawer"), it is caused by this stage's own change, and the binding rule for this run is that a defect introduced by the builder's own changes is a regression that must be fixed or reverted within the stage that caused it.

The corrective is small, is not a schema change, and is not a new feature, so scope permits it.

---

## Verification re-run (not taken from BASELINE.md)

| measurement | BASELINE.md claims | re-derived here | result |
|---|---|---|---|
| `scripts/verify.sh` at HEAD `75a8b31` | - | exit 0; OttoDomain 246, OttoPersistence 112, OttoUI **169**, total **527**; app target builds; `swiftlint --strict` clean | ✅ |
| OttoUI host tests at parent `3925084` | 168 | fresh `git clone` of the repo into a scratch dir, `checkout 3925084`, `swift test`: `Test run with 168 tests in 29 suites passed` | ✅ baseline reproduces |
| `406a5a6..3925084` is code-free | implied | `git diff --name-only` = `PROD-READINESS.md`, `reviews/BASELINE.md`, `reviews/REVIEW-0.md` only, so the 526/168 baseline carries to the parent | ✅ |
| simulator suite at HEAD | 19 tests, 7 known issues, `** TEST SUCCEEDED **` | `** TEST SUCCEEDED **`, `Test run with 19 tests in 3 suites passed after 2.967 seconds with 7 known issues`, exit 0 | ✅ identical |

Nothing is worse than baseline: +1 host test, simulator unchanged, lint clean.

**BASELINE.md reproducibility defect (recorded, not a stage finding).**
The simulator command as written in `reviews/BASELINE.md:12` fails when run from the repo root:
`xcodebuild: error: The project named "Otto" does not contain a scheme named "OttoUI-Package"` (exit 65), because the generated `Otto.xcodeproj` shadows the package.
It only reproduces from `Packages/OttoUI/`.
A baseline that cannot be re-run as recorded is weaker evidence than it looks.

## Falsification re-performed, exactly as the commit message describes

`ottoDayCalendar` switched to `.buddhist`, `swift test --package-path Packages/OttoUI --filter DisplayFormattingTests`:

```
✘ "calendar days render through the locale, never by interpolation" DisplayFormattingTests.swift:49:9:
   (day.displayText(locale: enCA) → "Aug 15, 1483") == "Aug 15, 2026"
✘ "a calendar day resolves to its Gregorian instant, not another calendar's" DisplayFormattingTests.swift:71:9:
   (day.displayDate() → 1483-08-15 05:17:32 +0000) == (expected → 2026-08-15 04:00:00 +0000)
✘ ... DisplayFormattingTests.swift:80:9:
   (day.displayDate() → 1483-08-15 05:17:32 +0000) != (misread → 1483-08-15 05:17:32 +0000)
✘ Test run with 7 tests in 1 suite failed after 0.038 seconds with 3 issues.
```

The two strings the commit message quotes reproduce verbatim.
The message says "both assertions fail"; three expectations fail across the two tests, which is imprecision, not fabrication.
Tree restored with `git checkout --` and confirmed clean (`git status --short` empty at HEAD `75a8b31`).

The era measurements in the commit message also reproduce exactly, on the same instant, `America/Toronto`:
`buddhist 2569-8-6, japanese 8-8-6, hebrew 5786-12-23, islamic-umalqura 1448-2-23, roc 115-8-6, persian 1405-5-15`.
No fabricated or unreproducible finding was found anywhere in this stage.

---

## Findings

### 1. P1 — REGRESSION: after this fix a non-Gregorian device schedules reminders that can never fire, because iOS re-resolves the day numbers in the device calendar

**severity:** P1, and P0 unconditionally for a user in a region where a non-Gregorian calendar is the default, by the ledger's own `ASSUMPTIONS 1` reasoning.

**evidence.**
`Packages/OttoUI/Sources/OttoServices/LiveNotificationClient.swift:226-232` builds the trigger from bare numbers with no calendar attached:

```swift
var components = DateComponents()
components.year = spec.year      // straight from reminder.day.year - NotificationScheduler.swift:340-344, :353-355
...
trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
```

A `DateComponents` with a nil `calendar` is resolved by `UNCalendarNotificationTrigger` in `Calendar.current`.
Measured directly against the real `UserNotifications` API (compiled Swift binary, this host, launched with `-AppleLocale th_TH@calendar=buddhist`):

```
Locale.current: th_TH@calendar=buddhist
Calendar.current.identifier: buddhist
components(no calendar) year=2026 -> nextTriggerDate: nil
components(no calendar) year=2569 -> nextTriggerDate: Optional(2026-08-15 13:00:00 +0000)
components(gregorian)   year=2026 -> nextTriggerDate: Optional(2026-08-15 13:00:00 +0000)
```

(Same binary under the host's own Gregorian locale returns `2026-08-15 13:00:00 +0000` for `year=2026`, so the difference is the device calendar and nothing else.)

Consequence, for a device that has been Buddhist throughout:

| | day numbers the scheduler emits | what iOS fires |
|---|---|---|
| **before** `75a8b31` | 2569 (`today` read through `Calendar.current`) | `2026-08-15 13:00 UTC` - the **correct** instant, because the two errors cancel |
| **after** `75a8b31` | 2026 (correct Gregorian) | `nextTriggerDate` = **nil** - 2026 BE is 1483 CE, in the past, so the request never fires |

The same inversion applies to every Gregorian-structured non-Gregorian calendar (ROC 115, Japanese Reiwa 8): before the change those devices got a five-second catch-up storm (R0-2's measured branch, `NotificationScheduler.swift:334,348,360`), which is loud and wrong; after it they get silence, which is this project's stated worst outcome.
Nothing self-heals: the scheduler's own `fireDate > now` test is Gregorian, so it sees every rung as comfortably in the future, never takes the catch-up branch, and keeps reporting a `coveredThrough` that Today renders as a coverage promise (`TodayView.swift:187-193`).
If `center.add` rejects a past-dated trigger instead of accepting it, the throw lands in `try await client.add(spec)` and is swallowed upstream (F5, F3) - both branches end in silence.
**UNVERIFIED on hardware** (device prohibited): the semantics above were measured against macOS `UserNotifications`, the same framework and class; on-device confirmation is out of reach this run.

**why the builder missed it.**
F1 was scoped by grepping for `Calendar.current` in Otto's own source, and this site contains no calendar at all - the device calendar enters through Foundation's default, not through a call the grep can see.
The ledger, Review 0 (R0-2) and this commit message all stop at `NotificationScheduler`'s internal `fireDate` comparison and treat that Gregorian instant as the delivery time.
It is not: it decides only which branch the scheduler takes.
The instant that reaches the user is computed by iOS, from the numbers, in the user's calendar - which is why the pre-fix system was internally consistent in "device-calendar numbering" and actually delivered, and why correcting one end of it without the other is worse than correcting neither.

**required correction (stated, not applied - reviewers do not edit code).**
Attach an explicit Gregorian calendar to the trigger components.
Note the layering trap: `ottoDayCalendar` is declared in `OttoStores` (`DisplayFormatting.swift:44`) and `OttoStores` *depends on* `OttoServices` (`Packages/OttoUI/Package.swift:30-43`), so `LiveNotificationClient` cannot import it.
The constant belongs in `OttoDomain`, next to `CalendarDay.fireDate`, which already hard-codes `.gregorian`.
Also weigh the deliberate no-timezone property documented at `LiveNotificationClient.swift:221-225`: `Calendar(identifier:)` carries a **fixed** timezone snapshot (measured below), so attaching a calendar wholesale can pin the fire time to the timezone in force when it was constructed.

### 2. P1 — the committed mechanism statement is contradicted by measurement

**severity:** P1, because it is the sentence that makes finding 1 invisible.

**evidence.**
Commit `75a8b31` message: *"Future-dated eras schedule reminders centuries out that never fire."*
`PROD-READINESS.md:62` and `reviews/REVIEW-0.md:97-113` carry the same claim in the other direction.
The measurement above shows that on the device in question the pending request does **not** fire centuries out: iOS reads year 2569 back as 2026 CE and delivers it on time.
The claim is true only of `NotificationScheduler`'s internal `fireDate`, and it is stated as the user-visible outcome.
This is the contract's "evidence citations that don't say what they're claimed to say", inside the commit message that closes the finding.

**why the builder missed it.**
The measurement stopped at the boundary where the number was computed instead of following it to the boundary where it is consumed - the same failure mode Review 0 named in R0-2 and then repeated one layer further down.

### 3. P2 — the added test cannot fail for the defect it names, and the recorded falsification does not test the change that was made

**severity:** P2.
Disclosed, not concealed - `DisplayFormattingTests.swift:53-62` and the commit message both state the limitation plainly, which is why this is not rated higher.

**evidence.**
The falsification on record breaks `ottoDayCalendar`'s *value*, not the change the commit makes (removing `Calendar.current`).
I performed the missing one: reverted `displayDate()` to `var calendar = Calendar.current`, left everything else at HEAD, and ran the suite.

```
✔ Test "a calendar day resolves to its Gregorian instant, not another calendar's" passed after 0.003 seconds.
✔ Test "calendar days render through the locale, never by interpolation" passed after 0.004 seconds.
✔ Test run with 7 tests in 1 suite passed after 0.010 seconds.
```

The guard is green against the exact defect it was written to prevent, and will be green on CI too (macOS runners are Gregorian).
Two of its three expectations (`:76-79`) compare Foundation to Foundation and cannot fail for any change to Otto's code.
So the suite went 168 → 169 without gaining a test that can detect this regression class.

An enforcement artifact that *can* fail already exists in this repo's idiom: `.swiftlint.yml:44-79` defines three `custom_rules` with `included`/`excluded` path regexes and `severity: error`.
A rule banning `Calendar.current` in the day/instant conversion files would fail `verify.sh` the moment the seam comes back.

**why the builder missed it.**
The falsification requirement was read as "make some assertion in the new test fail", and switching the constant does that.
The requirement is that the test fail *for the defect*, and this repository's own documented hazard is a green assertion that means nothing.

### 4. P2 — `ottoDayCalendar`'s doc claim "Every day/instant conversion goes through this" is false, and the constant is structurally unreachable from the layer that schedules

**evidence.**
`DisplayFormatting.swift:38-39` states: *"Every day/instant conversion goes through this, and none of them takes a calendar parameter, so there is no seam left to get it wrong."*
Two conversions do not go through it:
`OttoDomain/Models/CalendarDay.swift:177-182` (`fireDate`, its own `Calendar(identifier: .gregorian)`) and `OttoServices/NotificationContent.swift:147-157` (its own Gregorian, pinned to UTC).
A third, `LiveNotificationClient.swift:226-232`, uses no calendar at all (finding 1).
None of the three can reach the constant: `OttoDomain` is below `OttoStores`, and `OttoServices` is below it too (`Package.swift:30-43`).
The single funnel the comment describes cannot exist where it is currently declared.

**why the builder missed it.**
The four sites were enumerated from the finding, and the constant was placed in the file where the first of them lived rather than in the module all of them can see.

### 5. P2 — REGRESSION (minor): `InsightsView.monthText` now resolves through a process-lifetime timezone snapshot

**evidence.**
`InsightsView.swift:145` is now `ottoDayCalendar.date(from: components)` with no timezone assignment, while the two other sites changed in the same commit explicitly copy and set it (`DisplayFormatting.swift:50-51`, `DateProvider.swift:41-42`).
`ottoDayCalendar` is a global `let`, so its timezone is fixed at first use.
Measured on this host:

```
bare.timeZone       : America/Toronto
TimeZone.autoupdate : autoupdating America/Toronto
bare.tz == auto     : false
```

`Calendar.current` was re-read on every call and therefore tracked a timezone change; the global does not.
After the user moves west with the app resident, the day-1 instant falls into the previous month while `.formatted(.dateTime.month(.wide).year())` renders in the live timezone, so every Insights month label reads one month early.
Display only, no stored data, which is why it is P2 - but it is a behavior change introduced by this commit, not a pre-existing one.

**why the builder missed it.**
The other two sites were written by copying the calendar and setting the timezone; this one was written as a direct substitution of the global for `Calendar.current`, and the difference between "snapshot per call" and "snapshot per process" is invisible in a diff.

### 6. P2 — `DateProvider.live`'s own doc comment is now false

**evidence.**
`DateProvider.swift:30` still reads *"Reads the system clock and the device's current calendar."*
`:41-43` no longer reads the device's calendar; that is the entire point of the change, and the inline comment eight lines below contradicts the doc line above it.

**why the builder missed it.**
The inline comment was rewritten in full and the doc comment above the symbol was not re-read.

### 7. Informational — "proleptic" is a slight overstatement of `Calendar(identifier: .gregorian)`

`DisplayFormatting.swift:32-34` calls the domain proleptic Gregorian and presents `Calendar(identifier: .gregorian)` as its embodiment.
Foundation's `.gregorian` carries the 1582 Julian cutover; `.iso8601` is the proleptic one.
No practical impact for billing dates, and it matches the pre-existing `CalendarDay.fireDate`, so it is recorded rather than raised.

---

## Checked and found clean (recorded so severity is not inflated by omission)

- **The remaining `Calendar.current` in the app**, `SettingsView.swift:85,93`, is **not** a fifth F1 site.
  It round-trips only hour and minute through a fixed year-2000 anchor.
  Measured in all seven calendars: `hour=9 minute=30` comes back intact in every one, including the cases where the anchor lands in year 4018 or -1761.
  Not a defect.
- **No SwiftData schema change.** The diff touches five files, none of them a model, a schema version, or `OttoMigrationPlan`.
- **No prohibited action.** No `.github/workflows/` change, no dependency change, no narrative-document edit, no history rewrite (`git reflog` shows three ordinary commits), nothing pushed (`origin/main` still at `406a5a6`, four local commits ahead), no device contact.
- **No feature smuggled in.** `ottoDayCalendar` is an internal constant; no screen, toggle, export field, model, or config key was added.
- **No error handling that hides an error** was introduced by this diff; the `guard`/fallback shapes are the pre-existing ones with the calendar parameter removed.
- **No public-API regression** for callers: the only injected `calendar:` argument anywhere in the tree was `DisplayFormattingTests.swift:49`, and it was pinning Gregorian, which is now the only behavior.
- **`asDate()` is correct and improves the round trip:** the picker renders in the reader's calendar either way, and the numbers written back are now the domain's.
- **The ledger was not touched** by this commit, so nothing was marked resolved without an artifact.

## What must happen for this stage to pass

1. Close finding 1 within this stage - it is a regression from this stage's own change, not a NEXT ROUND finding - or revert `75a8b31` and re-land both halves together.
   The fix is the same class as the one already made, needs no schema change and no new capability, and its blast radius is one call site plus the timezone question noted above.
2. Correct the mechanism sentence in the commit message / ledger so it describes where the fire instant is actually computed (finding 2).
3. Either make the new guard capable of failing for a return of `Calendar.current` (the `custom_rules` route is in this repo's existing idiom) or state in the ledger that F1 has no executable regression guard on any environment this project can run (finding 3).

Findings 4, 5, 6 and 7 are small enough to fold into the same pass or to carry into NEXT ROUND with their evidence; findings 5 and 6 are this stage's own and should not be carried.
