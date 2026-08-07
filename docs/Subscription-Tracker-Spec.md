# Otto — Product & Technical Spec
### Subscription and free-trial tracker · iOS

**Status:** **v1.2** — revised Aug 6 late against Claude Code's Wave 2 report. Waves 0–2 complete and committed (`~/dev/otto`, 92 tests passing).
**App name:** Otto · **Bundle ID:** `com.arthurzhang.otto` (permanent)
**Created:** 2026-08-06
**Owner:** The owner
**Build model:** Claude Code implements · this chat plans, reviews, and holds the gates
**Companions:** `Software-Build-Ideas.md` · `Open-Tasks-and-Threads.md` · `PROMPT-Subscription-Tracker-Build.md`

---

## 1. Why this exists

Two real failures, both from the last month, define the product:

**Failure A — the silent trial conversion.** The owner signed up for a FoodApp free trial during the study term, never noticed it converted, and paid roughly **$11/month for two to three months for a service he never used**. Three separate things went wrong: he didn't know the trial's end date, nothing warned him before it converted, and once it was converting he wasn't using the service so nothing prompted him to notice.

**Failure B — the cancellation that didn't take.** the second user reviewed a credit-card statement and found a **charge for a service she had already cancelled**. The cancellation was performed; the billing didn't stop. Nothing was watching.

These are different bugs and they need different features. Failure A is a **forward-looking reminder** problem. Failure B is a **backward-looking verification** problem — and almost no consumer subscription tracker solves it, because they all treat "user marked it cancelled" as the end of the record.

**The product thesis:** a subscription's lifecycle does not end when you cancel it. It ends when you have confirmed the money stopped moving.

### Non-goals for v1

- The app **never acts on the user's behalf.** It does not cancel, does not log in to vendors, does not touch payment methods. It stores the cancellation URL and the instructions, and it reminds. *(Deliberately open for a much later version; explicitly out for v1–v3.)*
- The app **does not auto-discover** subscriptions from statements or email. Manual entry only. Discovery is a v2 track with its own spec.
- The app **does not give financial advice** — no "you should cancel this." It surfaces facts (cost, usage, trend) and the human decides. *(Same boundary as Kept's "never decides deductibility.")*

---

## 2. Scope and audience

| | v1 | Later |
|---|---|---|
| **Users** | The owner alone (dogfood), then the second user via TestFlight | a second user; then public |
| **Platform** | iOS native, SwiftUI | Web mirror → Android |
| **Currency** | CAD only, but the field exists on every record from day one | Multi-currency + FX at charge date |
| **Entry** | Manual | Statement/email discovery |
| **Distribution** | TestFlight | App Store, possibly paid |

**Track:** self-tooling now, commercial candidate later. Per the scope boundary in `Software-Build-Ideas.md` this starts on the self-tooling list; if it crosses to the commercial track that gets written down explicitly, not absorbed by momentum.

**Product philosophy (the owner's, recorded because it drives the architecture):** build several small apps that each solve one specific problem extremely well, polish each one, and only merge them into a suite *after* each has proven itself. The corollary for this build: **no shared infrastructure with Kept.** Separate repo, separate bundle ID, separate data store. What they may share later is a *pattern*, not a codebase.

---

## 3. The architecture decision

You asked me to think hard about this rather than optimise for the small initial audience. Here is the reasoning and the call.

### 3.1 The recommendation

**Ship v1 as: SwiftUI + SwiftData persistence + CloudKit private database sync. No server.**
**But structure the code so the server is a swap, not a rewrite.**

### 3.2 Why no server

The core feature — a notification firing on the right day — is **computed and delivered entirely on-device** by `UNUserNotificationCenter`. A server contributes nothing to it. Building a backend for v1 would mean owning auth, hosting, sync conflict resolution, and a security surface, in exchange for zero improvement to the thing the app is for.

CloudKit's private database additionally gives you, for free and correctly:

- **Backup.** If the second user drops her phone in a lake, her data is in her iCloud. A local-only app would lose it — that alone disqualifies local-only.
- **Multi-device sync** (iPhone → iPad) with battle-tested conflict handling.
- **Structural per-user isolation.** Her data lives in *her* iCloud, not in a database you operate. There is no cross-user leak to write a bug into.
- **No account creation.** the second user never makes a password. For a non-technical user this is the difference between "installed it" and "meant to install it."

### 3.3 The honest cost of that choice

**CloudKit private data is invisible to you as the developer.** You cannot read it, migrate it server-side, or bulk-move it. If you launch Android in 2028, every existing iOS user must personally run an export and upload it. That is a real one-way door and I don't want to pretend otherwise.

**The mitigation is not "build the server early."** It's this: the thing that makes a future backend expensive is a codebase where persistence types have leaked into the domain logic and the UI. Avoid that and the migration is a new adapter behind an existing protocol. Build the server now and you carry its cost for two years to avoid a cost you may never pay.

**Flip condition — the one case where I'd build the backend immediately:** if you decide you want Android or paid public distribution within roughly the next twelve months. Then the auth system, the server-side receipt validation, and the cross-platform data store all become required anyway, and CloudKit is throwaway work. If Android is a "someday, maybe," CloudKit is correct. **You own this call; the spec below works under either, because the domain layer is identical.**

### 3.4 The layering that makes it portable

Five layers, strict one-way dependencies (each layer knows only about the ones below it):

```
┌─────────────────────────────────────────────┐
│ 5. UI — SwiftUI views + @Observable models  │
├─────────────────────────────────────────────┤
│ 4. Services — NotificationScheduler,        │
│    ExportService, InsightsCalculator        │
├─────────────────────────────────────────────┤
│ 3. Repository protocols — SubscriptionRepo, │
│    BillingEventRepo (interfaces only)       │
├─────────────────────────────────────────────┤
│ 2. Persistence adapters — SwiftData impl    │  ← the swappable layer
├─────────────────────────────────────────────┤
│ 1. Domain — pure Swift structs + pure funcs │  ← zero framework imports
└─────────────────────────────────────────────┘
```

**Layer 1 is the important one.** `Subscription`, `BillingCycle`, `CalendarDay`, `nextBillingDate(...)`, `reminderSchedule(...)` are plain Swift value types and pure functions. They import **nothing** — no SwiftData, no SwiftUI, no `UNUserNotificationCenter`, ideally not even `Foundation` beyond `Calendar`/`DateComponents`. They are 100% unit-testable with no simulator, and they translate to Kotlin or TypeScript almost line-for-line if Android ever happens.

**Layer 2 absorbs a specific ugliness.** SwiftData models backed by CloudKit are subject to hard framework constraints — <cite index="10-1">no `@Attribute(.unique)`, every property must be optional or carry a default value, all relationship properties must be optional, and `deny` delete rules are unsupported</cite>. That produces model classes where everything is an optional with a default, which is miserable to write business logic against. **So don't.** The `@Model` classes are *persistence records only*; a mapping layer converts them to and from the clean, non-optional domain structs, and every mapping failure is handled explicitly rather than force-unwrapped. This is the single most important structural decision in the build, and it is also exactly what makes the persistence layer swappable.

### 3.5 Schema discipline for future portability

Cheap now, expensive to retrofit. Non-negotiable on every persisted record:

| Rule | Reason |
|---|---|
| Client-generated `UUID` primary key | No autoincrement to reconcile against a server later |
| `createdAt` / `updatedAt` as UTC instants | Last-write-wins conflict resolution needs them |
| Soft delete via `deletedAt` tombstone | Hard deletes cannot be synced; a deleted row must be *communicable* |
| `schemaVersion: Int` on the store | Migration needs to know what it's reading |
| Money as **integer cents**, never `Double` | Same rule as Kept. `0.1 + 0.2 != 0.3` |
| Billing dates as **calendar days**, not `Date` | See §4.1 — this is a correctness issue, not a style one |
| Export/import as a **first-class v1 feature** | It is simultaneously backup, user trust, and the Android migration path |

---

## 4. The date engine

This is the highest-risk component in the app. If it is wrong, the app is not merely imperfect — it is actively harmful, because the user has stopped watching their own subscriptions and delegated that to a tool firing on the wrong day.

### 4.1 A billing date is a calendar day, not a timestamp

If you store "renews Feb 28" as a `Date` (an instant), then a user who flies to Vancouver, or a device whose timezone changes, can see that instant resolve to Feb 27 in the new zone. The reminder fires a day early or late, silently.

**Rule:** introduce a `CalendarDay` value type holding `(year, month, day)` with no time and no zone. All billing arithmetic operates on `CalendarDay`. Conversion to a real fire-time `Date` happens **only** at notification-scheduling time, combining the calendar day with the user's preferred wall-clock hour in their *current* timezone. A timezone change triggers a full reschedule, and the day never moves.

### 4.2 Month-end anchoring — the rule real services use

You asked me to just use what real billing systems do. I checked Stripe's billing documentation, since it's the de-facto reference implementation:

> <cite index="6-1">A monthly subscription with a billing cycle anchor of January 31 bills on the last day of the month closest to the anchor — February 28 (or February 29 in a leap year) — then March 31, April 30, and so on.</cite>

The important half is the second half. It clamps to the short month, and then **returns to 31**. It does not become a 28th-of-the-month subscription forever. <cite index="1-1">Stripe's own documentation states the subscription is billed on the last day of that month and then reverts to its normal billing day the following month.</cite>

**The rule, stated precisely:**

1. Store `anchorDay` (1–31) as originally entered. **It is immutable.** Never overwrite it with a computed date.
2. To find the Nth billing date, advance N intervals from the anchor month, then set the day to `min(anchorDay, daysInThatMonth)`.
3. Always compute from the original anchor, never by adding an interval to the *previously computed* date. Iterating from computed dates is how drift gets in.
4. Annual subscriptions anchored to Feb 29 bill Feb 28 in common years and Feb 29 in leap years — same rule, applied to a year interval.
5. Day- and week-based cycles are plain arithmetic. No clamping. No anchor day.

### 4.3 Cycle model

One type, four units — not five separate cases:

```swift
struct BillingCycle {
    enum Unit { case day, week, month, year }
    let unit: Unit
    let interval: Int   // must be >= 1
}
```

- Weekly → `(.week, 1)` · Biweekly → `(.week, 2)`
- Monthly → `(.month, 1)` · Quarterly → `(.month, 3)` · Semiannual → `(.month, 6)`
- Annual → `(.year, 1)`
- Custom "every 45 days" → `(.day, 45)`

The UI presents friendly names; the domain stores one shape. Quarterly gets month-end clamping for free because it *is* a month cycle.

### 4.4 Required test cases (Wave 1 gate)

The build does not proceed past Wave 1 until all of these pass:

| Input | Expected sequence |
|---|---|
| Jan 31, monthly | Feb 28, Mar 31, Apr 30, May 31, Jun 30, Jul 31 |
| Jan 31, monthly, leap year | Feb 29, Mar 31, Apr 30 |
| Jan 30, monthly | Feb 28, Mar 30, Apr 30 |
| Aug 31, quarterly | Nov 30, Feb 28/29, May 31 |
| Feb 29 2024, annual | Feb 28 (2025), Feb 28 (2026), Feb 28 (2027), **Feb 29 (2028)** |
| Mar 15, monthly, 24 iterations | Always the 15th; no drift |
| Every 45 days from Nov 20 | Jan 4 — correct across the year boundary |
| Weekly from a Friday, across a DST transition | Always Friday |
| Any cycle, device timezone changed mid-sequence | Calendar days unchanged |

**⚠ The property test in v1.0 was wrong, and is corrected here.** It read: *"iterating N intervals forward and N back must return the original anchor day."* **That is impossible under clamping, and would have been impossible to satisfy.** Stepping backwards from a clamped date destroys information — a Feb 28 landing could have come from an anchor of 28, 29, 30, or 31, and nothing can distinguish them after the fact. An implementation cannot pass it, so it would have been either deleted or "fixed" by weakening the implementation.

**The corrected property, in three parts** — all of which a naive iterate-from-computed-dates implementation fails, which is the point:

1. **Anchor recovery at occurrence 0.** For any anchor day 1–31, any month or year cycle, and any N: computing occurrence 0 *after* advancing N occurrences returns exactly the anchor. The anchor is never mutated by traversal.
2. **Month arithmetic reverses exactly.** The month/year component of occurrence N, stepped back N intervals, lands on the anchor's month and year — the reversibility that *does* hold, at the level where no information is lost.
3. **No clamp leaks forward.** For every occurrence, the landing day equals `min(anchorDay, daysInThatMonth)`. A clamp is never allowed to become the new anchor.

*(Corrected Aug 6 after Claude Code's Wave 1 report identified the original as unsatisfiable. Recorded rather than quietly replaced: a test suite passing against a weakened assertion is worse than no suite, and the failure mode here was a spec that invited exactly that.)*

---

## 5. Data model

### 5.1 `Subscription`

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | client-generated |
| `name` | String | "FoodApp", "Netflix" |
| `vendorURL` | URL? | account/manage page |
| `category` | Category | fixed enum, §5.6 |
| `status` | Status | `.trial` `.active` `.paused` `.cancellationPending` `.cancelled` `.archived` |
| `amountCents` | Int | current price |
| `currencyCode` | String | "CAD" in v1; field exists day one |
| `cycle` | BillingCycle | §4.3 |
| `cycleStartDay` | CalendarDay | **`let`. The single anchor of record.** May be user-entered (Mode A) or back-derived (Mode B). |
| ~~`anchorDay`~~ / ~~`anchorMonth`~~ | — | ❌ **Removed in v1.1.** Both are **derived** from `cycleStartDay`, never stored. Storing all three was redundant state that could disagree; making `cycleStartDay` a `let` enforces §4.2's immutability rule *in the type system* instead of by discipline. |
| `reminderLeadDays` | Int | **per-subscription**, defaults from settings |
| `sameDayReminder` | Bool | default `false`. **Added v1.1** — §6.3 offered an optional same-day renewal reminder with no field to control it. |
| `pauseEndsOn` | CalendarDay? | **Added to the table in v1.1** — it existed only in prose below. |
| `paymentMethodID` | UUID? | |
| `cancellationURL` | URL? | |
| `cancellationNotes` | String? | "phone only, 1-800-…, mention retention offer" |
| `lastUsedDate` | CalendarDay? | see §7.3 |
| `notes` | String? | |
| `createdAt` / `updatedAt` / `deletedAt` | Date / Date / Date? | UTC |

**Entry modes (both required).** Some subscriptions you know the start date for; Netflix you've had for two years and have no idea. So:

- **Mode A — "I know when it started":** enter start date + cycle → next billing date is computed.
- **Mode B — "I know my next charge":** enter next billing date + cycle → the anchor is *back-derived* from it.

Both write the same fields. Mode B is what most existing subscriptions will use, and getting it wrong makes onboarding painful enough that the app doesn't get used.

**Mode B is the identity function, and that is correct — not lazy.** The entered next-charge date *is* a real occurrence of the sequence, so it anchors it directly at occurrence 0. Stepping one cycle backwards to find an "earlier" anchor would manufacture drift: back-stepping from Mar 31 yields a Feb 28 anchor, and the subscription then bills the 28th forever. That is precisely the bug §4.2 exists to prevent.

**⚠ Known limitation, with a UI mitigation (v1.1).** Mode B cannot recover an anchor that clamping has already destroyed. A user who enters "next charge: Feb 28" for a subscription the vendor actually anchors on the 31st gets a 28th-anchored sequence in Otto, and the two diverge from March onward. There is no way to derive the truth from that input — but Otto errs *early* (28 before 31), which is the safe direction for a reminder app.

**Mitigation:** when the entered date is the last day of a month shorter than 31 days, the Add screen must ask one question — *"Is this the last day of the month, or specifically the 28th?"* — and set the anchor to 31 or 28 accordingly. One tap, and it removes the only systematic inaccuracy in the entry path.

**On `.paused`.** A paused subscription is one the vendor has suspended billing on but the user has not cancelled — a gym freeze, a seasonal hold, a plan on hiatus. It is a distinct state, not a flavour of cancelled, and it has three specific behaviours:

- **No `BillingEvent` rows are generated while paused**, and no renewal reminders fire.
- **It still counts toward the subscription list but not toward monthly burn** — Insights must show paused spend as a separate line, or the burn figure lies. **Formula (pinned in v1.1, was previously undefined):** paused spend uses the **monthly-equivalent at the price frozen when the pause began**, and a `PriceChange` recorded during a pause does **not** take effect until the subscription resumes. Without pinning this, Wave 7's numbers are arbitrary.
- **An optional `pauseEndsOn: CalendarDay?`** schedules a resume reminder. Un-paused-by-accident is a real failure mode: the vendor resumes billing on schedule and the user has stopped watching.

*(Added Aug 6 after a competitive scan — every shipping tracker in the category models paused as a first-class state, and retrofitting it once the `BillingEvent` ledger has history is materially harder than including it now.)*

### 5.0 The audit quartet — on **every** persisted record *(added v1.2)*

**⚠ v1.0 and v1.1 contradicted themselves here, and the contradiction is resolved in §3.5's favour.** §3.5 called client UUID + `createdAt`/`updatedAt` + soft-delete tombstone "non-negotiable on every persisted record," while the §5 tables below gave them to `Subscription` alone — `BillingEvent`, `CancellationRecord`, `PriceChange` and `PaymentMethod` had no timestamps, and `TrialTerm` and `CancellationRecord` had no `id` at all.

**Every model carries all four**: `id: UUID` (client-generated), `createdAt: Date`, `updatedAt: Date`, `deletedAt: Date?`. Read the §5 tables below as listing each model's *distinctive* fields, with the quartet implied.

Two reasons this isn't bookkeeping ceremony:

- **CloudKit syncs per record, not per object graph.** A `BillingEvent` edited on an iPhone and an iPad has nothing to resolve last-write-wins against without its own `updatedAt`. The parent's timestamp doesn't help — the parent didn't change.
- **A record with no `id` cannot be addressed individually by CloudKit at all**, which makes `TrialTerm` and `CancellationRecord` unsyncable as written.

Fixing this **before Wave 6 is a field addition; after it is a schema migration** on data already living on two people's phones.

### 5.2 `TrialTerm` (optional, attached to a Subscription)

| Field | Type | Notes |
|---|---|---|
| `startDate` | CalendarDay | user-entered |
| `lengthDays` | Int | user-entered — **not** the end date |
| `conversionDate` | CalendarDay | **computed** = start + length |
| `bufferDays` | Int | default 2, user-editable |
| `cancelByDate` | CalendarDay | **computed** = conversion − buffer |
| `convertsToAmountCents` | Int | what it becomes; often the whole point |

Per your instruction, the user enters the two things they actually know (when it started, how long it runs) and the app derives everything else. The user should never be asked to do date arithmetic — that arithmetic failing is the entire reason the FoodApp charge happened.

The **cancel-by buffer** exists because cancelling on the conversion day is already too late at some vendors, and because a reminder that fires while you're in a lecture needs slack. Default 2 days, adjustable per trial.

### 5.3 `BillingEvent` — the ledger

Every expected charge is a row. This is the backbone of both verification and reporting; without it the app has no memory.

| Field | Type |
|---|---|
| `id` | UUID |
| `subscriptionID` | UUID |
| `expectedDate` | CalendarDay |
| `expectedAmountCents` | Int |
| `state` | `.upcoming` `.confirmedCharged` `.confirmedNotCharged` `.unexpectedCharge` `.skipped` |
| `userConfirmedAt` | Date? |
| `actualAmountCents` | Int? | if it differed → triggers a price-change prompt |

**When rows are created (specified in v1.1 — previously undefined, and a Wave 2 blocker).** Future billing dates are a **pure function of the anchor and the cycle**, so storing them in advance duplicates derived state and grows the table without bound.

**Rule: a `BillingEvent` is materialized at the moment its reminder is scheduled, and never earlier.** Concretely — the reminder scheduler runs, computes the events inside the rolling ~90-day horizon, and creates any that don't yet exist. Rows past the horizon do not exist; the UI derives those dates on the fly.

**Which window governs — the reminder's, not the charge's** *(pinned in v1.2; v1.1 left the two unreconciled)*. A reminder fires `reminderLeadDays` *before* its charge, so a reminder inside the horizon can belong to a charge that falls just outside it. Since the entire reason a row exists is to carry that reminder's state, **the row must exist whenever the reminder does.**

> Materialize every charge date in `[today, today + horizonDays + maxReminderLeadDays]`.

The charge window is therefore slightly wider than the reminder horizon, by the largest lead time in use. Deriving it from the charge window instead leaves the outermost reminders with no row to attach to.

**Which statuses materialize** *(unspecified in v1.1)*:

| Status | Materializes? | Why |
|---|---|---|
| `.active` | ✅ Yes | The ordinary case |
| `.trial` | ✅ **Exactly one**, at `conversionDate`, for `convertsToAmountCents` | ⭐ **Otherwise the single most important charge in the app has no ledger row.** The trial conversion is the charge Otto exists to catch; without a row, neither verification nor price-mismatch detection covers it |
| `.paused` | ❌ No | §5.1 — no charges while paused |
| `.cancellationPending` / `.cancelled` | ❌ Not prospectively | A `BillingEvent` asserts a charge is *expected*, which is the opposite of what the record claims. These are watched by §5.4 verification instead |
| `.archived` | ❌ No | Terminal |

**The one retrospective creation path.** When a verification reports `.stillCharging`, that charge **did** happen and needs a ledger row — created at that moment with state `.unexpectedCharge`. This is the **only** producer of that state; in v1.1 the enum case existed with nothing able to create it.

The justification is that a row only earns storage once there is **user-facing state to attach to it** — a reminder that fired, a confirmation, an amount mismatch. Before that it is a calculation, not a record. This also caps the ledger's growth at roughly `subscriptions × cyclesPerQuarter` new rows per scheduling pass.

### 5.4 `CancellationRecord` — the Failure-B fix

| Field | Type |
|---|---|
| `subscriptionID` | UUID |
| `markedCancelledAt` | Date | UTC instant — records *when the user acted*, and is **never** used for date arithmetic (see below) |
| `nextChargeDateIfNotCancelled` | CalendarDay | **Non-optional. Renamed and made required in v1.1.** |
| `verificationState` | `.pending` `.verifiedStopped` `.stillCharging` |
| `verifiedAt` | Date? |
| `evidenceNote` | String? | confirmation number, screenshot reference, rep's name |

**Why that field is now required, and renamed (v1.1).** As originally written it was optional, and the fallback was "the next billing date after today." That fallback is unimplementable in the domain layer: `markedCancelledAt` is a UTC instant, and §4.1 forbids converting an instant to a calendar day without a timezone — so the domain cannot derive the check date at all, and any runtime fallback drifts later every day the app goes unopened. **The date is fully computable at cancellation time** from the immutable anchor and the cycle, so it is computed once, then, and stored.

The rename matters too: *"expected final charge"* is ambiguous — some vendors bill once more, most don't. The field's actual job is to name **the date a charge would land if the cancellation silently failed**, which is exactly the verification trigger. `nextChargeDateIfNotCancelled` says that.

**A cancelled subscription is not archived until verification passes.** It stays in a "Watching" state and the app checks back on the next date a charge would have landed. If the user reports a charge did arrive, the record flips to `.stillCharging` and the app surfaces everything needed for a dispute: cancellation date, confirmation note, the charge date and amount.

**When a verification check goes unanswered** *(specified in v1.2; v1.1 was silent, and §6.2's catch-up rule covers reminders-before-a-billing-date, not this)*. The user opens the app a week after the check date and the state is still `.pending`.

**Rule: keep watching, and roll the check forward to the next date a charge would have landed — but cap it at three consecutive unanswered cycles.** A cancellation that silently failed will charge again next cycle, so one ignored notification must not end the watch. But past three, the signal is that notifications aren't reaching this item, and a fourth won't either: the subscription moves to a **persistent card in Today's *Needs action* section** and stops generating notifications. Escalating in the app rather than escalating the notifications is the correct response to being ignored.

### 5.5 `PriceChange` and `PaymentMethod`

`PriceChange`: `id`, `subscriptionID`, `effectiveDate`, `oldAmountCents`, `newAmountCents`, `recordedAt`, `source` (`.userEdit` / `.chargeMismatch`), `note`. Editing a price never overwrites history — it appends. This is what lets Insights show "Netflix has gone up 34% in three years."

`PaymentMethod`: `id`, `label` ("Bank Mastercard ••4821"), `last4`, `issuer`, `expiryMonth`, `expiryYear`, `isDefault`. Card-expiry warnings fall out of this for free, and the second user runs multiple cards so it earns its place in v1.

### 5.6 `Category` — fixed enum

Streaming & Video · Music & Audio · News & Reading · AI & Software Tools · Cloud & Storage · Gaming · Fitness & Health · Food & Delivery · Shopping & Memberships · Phone & Internet · Finance & Insurance · Education & Courses · Other

Fixed rather than free-form so the rollups mean something — free-form categories produce "AI", "ai tools", and "LLM" as three separate lines. `Other` plus a note field is the escape valve. Raw values are stable strings, never enum ordinals, so reordering the list later doesn't corrupt stored data.

---

## 6. The notification engine

### 6.1 The hard constraint

**iOS permits a maximum of 64 pending local notifications per app.** Anything scheduled beyond that is silently dropped. With trials taking three slots each, the ceiling arrives around twenty subscriptions — and the ones dropped are the furthest out, which are the annual renewals you most need warning about. Get this wrong and the app fails in exactly the way it exists to prevent, without any error appearing.

**Solution: a rolling horizon plus a deterministic priority budget.**

1. Schedule only within a rolling ~90-day horizon.
2. Allocate the 64 slots by priority:
   - **P1** — all trial notifications in the horizon (unrecoverable money, and there are few)
   - **P2** — all cancellation-verification checks
   - **P3** — renewal reminders, nearest-date first
   - **P4** — usage check-ins
3. If P3 overflows, drop furthest-out first and record the truncation date.
4. The UI **states the horizon**: "Reminders scheduled through 12 Nov." Never let the user believe coverage extends further than it does.

The budgeting function is pure and unit-tested against a synthetic 200-subscription fixture.

### 6.2 Rescheduling triggers

Scheduling is **idempotent**: cancel all pending, recompute, reschedule. Notification identifiers are deterministic — `"<subscriptionID>|<ISO date>|<kind>"` — so a double-run cannot produce duplicates. Triggers:

- App enters foreground
- Any subscription created, edited, or deleted
- A notification is delivered or acted on
- `BGAppRefreshTask` (registered for daily execution)
- `NSSystemTimeZoneDidChange` and significant-time-change notifications
- Notification permission newly granted

**Catch-up rule (added v1.1 — a real product bug, not a nicety).** If a reminder's computed day is already in the past but its billing date is still in the future, **schedule it immediately** rather than skipping it. Without this, Mode B onboarding silently fails in its most common case: the user adds a subscription because they noticed a charge coming in two days, the default 3-day lead is already past, and **no reminder fires for the exact charge that prompted them to add it.** If the notification hour has not yet passed today, fire at that hour; otherwise fire on the next scheduler run.

### 6.3 The reminder ladders

**Renewal (ordinary):** one notification at `reminderLeadDays` before, plus an optional same-day one controlled by `sameDayReminder` (§5.1; the field was missing in v1.0 — the feature had no data model).

**Trial (aggressive — this is Failure A):**
1. At `reminderLeadDays` before `cancelByDate`
2. Morning of `cancelByDate` — **time-sensitive**
3. Evening of `cancelByDate` — **time-sensitive**
4. If still unacknowledged, repeat daily until the conversion date passes

**How the daily repeat is implemented (resolved in v1.1).** "Repeat until acknowledged" depends on runtime state, which cannot be precomputed by a pure `reminderSchedule` — and if Wave 4 schedules the repeats anyway, they consume P1 slots the budget never counted. Two options existed; the choice is deliberate:

**Repeats are pre-scheduled and budgeted, not rescheduled reactively.** The full daily ladder from `cancelByDate` through `conversionDate` is planned up front, counted against the 64-slot budget as P1, and the remainder is **cancelled** when the user acknowledges.

The reason is that reactive rescheduling requires the app to run — and `UNUserNotificationCenterDelegate` fires only when the app is in the foreground or the user interacts with the notification. **The user ignoring the notification is precisely the scenario the escalation exists for**, so a mechanism that depends on their engagement fails exactly when it is needed. Pre-scheduling costs slots; reactive scheduling costs correctness.

**Bounded by construction:** repeats never extend past `conversionDate`, and the buffer defaults to 2 days, so a trial's ladder is at most ~5 notifications. Cap it at 5 regardless.

Time-sensitive interruption level lets these break through Focus modes. It requires the Time Sensitive Notifications entitlement — request it in Wave 0, not at submission.

The escalation exists because **a notification is not persistent**. Swipe it away at 7am and it is gone forever. For a $200 annual renewal that is a real loss, so trials get repetition and renewals don't.

**Cancellation verification:** fires on the first date a charge would have landed post-cancellation. *"You cancelled FoodApp on 12 Aug. A charge was due today. Check your statement — did it stop?"*

**Pause resume:** one notification on `pauseEndsOn`. *(Added in v1.1 — §5.1 promised a resume reminder while the reminder-kind list had no kind for it, so it would have been mislabelled as a renewal. Priority P3.)*

**Usage check-in:** every 90 days per active subscription, counted from `lastUsedDate`, falling back to the anchor when no use has ever been recorded. *"Have you used FoodApp since May?"* → No, twice running → flagged in Insights as a zombie.

### 6.4 Notification actions

Registered via `UNNotificationCategory`. Tap opens the subscription detail. Three buttons:

| Action | Behaviour |
|---|---|
| **Keeping it** | Marks the `BillingEvent` acknowledged. Silences this cycle only; reminders resume next cycle. |
| **I'm cancelling** | Sets `.cancellationPending`, opens the stored cancellation URL, creates a `CancellationRecord`, schedules the verification check. |
| **Remind me later** | Snooze — **hard-capped so it can never move past the `cancelByDate`.** A snooze that skips the deadline is a bug that costs money. |

All three must work from the background without launching the UI, and must be safe to invoke twice (the system can redeliver).

---

## 7. Screens

### 7.1 v1 screens

1. **Today** — the home screen, three sections: **Needs action** (trials inside their cancel-by window, pending verifications, failed verifications), **Next 30 days**, **Later**. If Needs action is empty, say so plainly rather than showing a blank list.
2. **Subscriptions** — full list, sort by next date / cost / name / category, filter by status. Each row shows the monthly-equivalent cost so a $120/yr and a $10/mo compare at a glance.
3. **Add / Edit** — the make-or-break screen. Entry Mode A vs B (§5.1), trial toggle revealing the trial block, category, amount, payment method, cancellation URL and notes, per-subscription lead time.
4. **Detail** — status, next charge, the billing-event ledger, price history chart, cancellation info, actions.
5. **Cancellation flow** — mark cancelling → capture confirmation number/notes → open vendor URL → schedule verification.
6. **Verification prompt** — "Did the charge stop?" Yes → archive. No → `.stillCharging`, plus a dispute summary the user can screenshot or read to the bank.
7. **Insights** — §7.2.
8. **Payment methods** — list, card-expiry warnings, per-card subscription totals.
9. **Settings** — default lead days, default trial buffer, notification time of day, export/import, iCloud sync status, notification permission state.

### 7.2 Insights

- **Monthly burn** (all cycles normalised) and **annualised total**
- **By category** — the view that answers "how much am I actually spending on AI tools"
- **Next 12 months**, month by month — annual renewals cluster and this is where you see it
- **Price-increase log** across all subscriptions
- **Zombie flags** — see below

**Normalisation rule (must be stated in code):** monthly-equivalent = amount × (30.4375 / cycleLengthInDays). Round **only at display**; never round a stored value. Annual = monthly × 12.

### 7.3 Zombie detection — the other half of Failure A

The FoodApp charge wasn't only a date problem. It was **$11/month for something he wasn't using**. A tracker that reminds you a charge is coming but never asks whether you want it has solved half the problem.

So: a `lastUsedDate` field, a 90-day check-in notification, and an Insights section listing subscriptions with no recorded use in 90+ days alongside what they've cost over that window. Not a recommendation to cancel — a fact, presented plainly, with the annual number attached.

---

### 7.4 Competitive position — what the category does not do

Scanned Aug 6, 2026. The established players are Rocket Money, ReSubs, SubTracker, Bobby, Subsly, Subtrack, Subby, Tilla, Trackery, Copilot, and YNAB. Three findings that matter to this build:

**1. Post-cancellation verification is unserved.** Every tracker reviewed offers reminders, spending analytics, and in some cases step-by-step cancellation guides. **None of them keeps watching after you cancel.** The universal model treats "user marked it cancelled" as the terminal state of the record. the second user's failure — a cancellation performed, charges continuing, noticed weeks later by chance — is therefore a gap across the whole category, not a feature the owner is reimplementing. **If this app ever crosses to the commercial track, this is the wedge**, and §5.4 is the differentiating code.

**2. The architecture has a shipped precedent.** Trackery runs manual entry with data that never reaches a company server, syncing only through the user's own iCloud — the same design as §3.1, in production and reviewed well. This is external evidence for the CloudKit call, not proof, but it does retire the concern that iCloud-only is an unusual choice for this class of app.

**3. Naming is a solved problem in the wrong direction.** Six of the eleven names are "sub" plus a suffix, and the category's best-regarded iOS app is *Bobby* — a human name that describes nothing. Hence **Otto**: proper noun, no feature description baked in, nothing to strand a later scope expansion.

**What not to copy:** several trackers gate renewal reminders behind a paid tier. Reminders are the entire product here — that is not a v1 or v-any consideration.

---

## 8. Build waves

Each wave ends in a commit and a checkpoint. Gates marked ⛔ do not pass without explicit sign-off.

| Wave | Contents | Gate |
|---|---|---|
| **0** ✅ | XcodeGen (`project.yml` committed, `.xcodeproj` generated + gitignored), bundle ID, entitlements, SwiftLint, CI, folder structure per §3.4 | ✅ **Done** — commit `e844ccf`. ⚠ CI written but **unverified until a remote exists**; uses `runs-on: macos-26` |
| **1** ✅ | Domain layer + date engine + tests, as a standalone SPM package (`Packages/OttoDomain`) so "Foundation only" is compiler-enforced | ✅ **Done** — commit `f36f584`; **50 tests / 11 suites passing**, incl. the 186-case property test |
| **2** ✅ | SwiftData models, mapping layer, repository protocols + implementations, as a second SPM package (`Packages/OttoPersistence`) so the layer boundary is compiler-enforced. Local only — **CloudKit explicitly `.none`** | ✅ **Done** — commits `fcdcf2d` / `92879f9` / `634e209` / `4b9db37`; **92 tests passing** (51 domain + 41 persistence), incl. a mutation-tested CloudKit-compatibility assertion |
| **3** | Core UI: Today, Subscriptions, Add/Edit (both entry modes), Detail | Can add a real subscription and see it |
| **4** | Notification engine: scheduling, slot budgeting, actions, reschedule triggers | ⛔ 200-subscription fixture stays within 64 slots with correct priority |
| **5** | Trial flows, cancellation flow, verification flow | ⛔ End-to-end trial test on device with a compressed timeline |
| **6** | CloudKit enablement + two-device sync verification | ⛔ Data survives delete-and-reinstall |
| **7** | Insights, payment methods, zombie detection | Numbers reconcile against a hand-computed fixture |
| **8** | Export/import (JSON + CSV), settings, accessibility, Dynamic Type, VoiceOver | Export → wipe → import restores exactly |
| **9** | Real-data dogfood; then TestFlight to the second user | The owner runs it as his only tracker for two weeks |

**Wave 1 before anything else, deliberately.** The date engine is the part that is silently wrong rather than loudly broken, and it is far easier to trust when it exists as pure functions with no UI attached.

---

## 9. Environment

- **Deployment target: iOS 26.0.** <cite index="19-1">iOS 26 is the current public release, at 26.5 as of mid-2026</cite>, and both devices in scope run current software — so there's no reason to carry compatibility shims for older versions.
- ⚠ <cite index="18-1">iOS 27 is in developer beta since June 8, 2026, with public release expected September 2026</cite> — which lands right in the middle of this build. **Develop against the iOS 26 SDK; test on an iOS 27 beta device before shipping to the second user.** Notification behaviour and Focus-mode handling are exactly the sort of thing that shifts in a major release.
- Swift 6 language mode, strict concurrency on from Wave 0. Retrofitting it later is significantly worse.
- Xcode's current release; **SwiftLint only** in CI. *(v1.0 named swift-format alongside it; the two overlap and the second earns nothing. Dropped so the spec and the repo agree.)*

---

## 10. Open decisions

| # | Decision | Status |
|---|---|---|
| 1 | App name + bundle ID | ✅ **Decided Aug 6 — Otto / `com.arthurzhang.otto`.** Permanent. |
| 2 | Android or paid public distribution within 12 months? | ⏸ **Open — does not block the build.** If yes, §3.1 flips to a real backend. Revisit at Wave 6, before CloudKit is switched on. |
| 3 | Notification time-of-day default | Default set: **09:00 local**, user-editable |
| 4 | Default reminder lead days | Default set: **3 days renewals · 5 days trials**, per-subscription override |
| 5 | Default trial buffer | Default set: **2 days**, per-trial override |

**On the name.** The bundle ID is permanent; the App Store display name is not, and can be changed at any time. So the durable half of this decision is the identifier, and it was chosen to be a proper noun carrying no feature description — a bundle ID like `com.arthurzhang.subtracker` would strand the app the moment it did anything beyond subscriptions. **Otto** additionally echoes *auto*-renewal without stating it, and follows the one naming strategy that has actually worked in this category (§7.4).

| 6 | Add a remote and verify CI | ⏸ Open — `runs-on: macos-26` is unverified until the first push; adjust the runner label if GitHub's differs |

**Decision 2 is the only one with a real deadline.** It is free to defer until Wave 6, and expensive after — once the second user has months of data in her private CloudKit database, moving her off it requires her cooperation rather than a migration script.

---

## Update log

- **2026-08-06 (late — v1.2, revised against the Wave 2 report)** — Wave 2 shipped: **92 tests passing**, persistence split into its own SPM package so the layer boundary is enforced by access control rather than convention, `@Model` classes `internal` to it, CloudKit set explicitly to `.none` rather than left `.automatic`. Four spec corrections, one of which was a gap **neither** side had noticed:
  - **⚠ §3.5 and the §5 tables contradicted each other on the audit fields.** §3.5 called `id`/`createdAt`/`updatedAt`/`deletedAt` non-negotiable on every record; the §5 tables gave them to `Subscription` alone, leaving `TrialTerm` and `CancellationRecord` with no `id` at all. **Resolved in §3.5's favour via a new §5.0**, because CloudKit syncs per record — a `BillingEvent` edited on two devices has nothing to resolve against without its own `updatedAt`, and a record with no `id` is unaddressable. **Fixing it before Wave 6 is a field addition; after, a migration on live data.**
  - **⭐ `.trial` had no materialization path — the gap neither of us caught.** v1.1 never said which statuses create `BillingEvent` rows; Claude Code inferred `.active` only, which is defensible but would have left **the trial conversion charge with no ledger row** — the exact charge the app was built to catch, invisible to both verification and price-mismatch detection. Now specified: `.trial` materializes exactly one event at `conversionDate`.
  - **The materialization window was ambiguous.** A reminder fires *before* its charge, so a reminder inside the horizon can belong to a charge outside it. Pinned: **the reminder window governs**, charge dates materialize through `horizon + maxReminderLeadDays`.
  - **`.unexpectedCharge` had no producer.** The enum case existed with nothing able to create it. Now specified as the retrospective row a `.stillCharging` verification writes.
  - **Unanswered verification checks were undefined.** Now: roll forward to the next would-be charge date, **capped at three consecutive unanswered cycles**, then escalate to a persistent card in Today rather than more notifications — escalating *in the app* is the right answer to being ignored, not escalating the notifications.

- **2026-08-06 (evening — v1.1, revised against Claude Code's Wave 1 report)** — Waves 0–1 shipped (`~/dev/otto`, commits `e844ccf` / `f36f584`, 50 tests passing). The implementation report surfaced **four genuine defects in this spec plus five underspecifications**, all now fixed here. Recorded individually rather than as a blanket "revised", because two of them were the kind that produce silently wrong software:
  - **⚠ The §4.4 property test was unsatisfiable.** "Advance N, step back N, recover the anchor" cannot hold under clamping — a Feb 28 landing is indistinguishable between anchors 28, 29, 30 and 31, so the information is gone. A spec that asks for an impossible test invites the test being weakened to match whatever the code does, which is worse than having no test. **Replaced with three properties that do hold**, chosen so a naive iterate-from-computed-dates implementation fails all three.
  - **⚠ The cancellation verification check was underivable.** `nextChargeDateIfNotCancelled` (renamed from `expectedFinalChargeDate`) is now **required**, because the optional-plus-fallback design was unimplementable: the fallback needed an instant→calendar-day conversion that §4.1 forbids. **This is the app's differentiating feature**, and as written it could not be built correctly.
  - **⚠ Mode B onboarding silently skipped its first reminder** — add a subscription three days before a charge with a 3-day lead and nothing fires for the charge that motivated adding it. **Catch-up rule added to §6.2.**
  - **⚠ The trial daily-repeat contradicted the pure-plan model.** Resolved in favour of **pre-scheduled and budgeted**, on the reasoning that reactive rescheduling depends on the app running, and the user ignoring the notification is exactly the case the escalation exists for.
  - **Redundant anchor state removed** — `anchorDay`/`anchorMonth` are derived, not stored; `cycleStartDay` is a `let`, moving §4.2's immutability rule from prose into the type system.
  - **Also specified:** when `BillingEvent` rows materialize (at reminder-scheduling time, never earlier) — a Wave 2 blocker; the paused-burn formula; a `pauseEnding` reminder kind and a `sameDayReminder` field, both features that had been described with no data model behind them; `truncatedAfter` semantics; usage check-in reference point; the Feb-29 row in §4.4, which was garbled.
  - **Added:** Mode B's known limitation (clamped anchors are unrecoverable) with a one-tap UI mitigation.
  - **Dropped** swift-format from §9 so the spec and repo agree on tooling.

- **2026-08-06 (later — name decided, competitive scan, `.paused` added)** — **Name and bundle ID locked: Otto / `com.arthurzhang.otto`.** Reasoning recorded in §10 rather than just the outcome, because the *durable* half of the choice was the identifier, not the label: display names are freely changeable, bundle IDs are not, so the ID was chosen to carry no feature description. Competitive scan added as **§7.4** with the load-bearing finding that **no shipping tracker in the category verifies that a cancellation actually stopped the charges** — the second user's failure is a category-wide gap, which makes §5.4 the wedge if this ever crosses to the commercial track. Same scan surfaced **`.paused` as a missing status**; added to §5.1 with its three behaviours specified, since retrofitting a status after the `BillingEvent` ledger has history is materially harder. Open decisions reduced from one blocker to **zero**; the Android/backend question is reframed as a deferrable Wave-6 checkpoint rather than an unresolved fork.

- **2026-08-06** — Document created. Scoped in-session from two concrete failures (FoodApp silent trial conversion; the second user's post-cancellation charge). Architecture decision recorded with its flip condition. Month-end anchoring rule set to clamp-without-drift, matching Stripe's documented behaviour, after the owner asked for whatever real billing systems use. Notification slot ceiling (64) identified as a load-bearing constraint and given a priority-budget design. Zombie detection added as the second half of the FoodApp failure — the original spec only addressed the date half.
