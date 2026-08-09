# Otto — Product & Technical Spec
### Subscription and free-trial tracker · iOS

**Status:** **v2.5 — MAIN SCHEMA FROZEN (V3).** ⭐ **Otto runs on the owner's iPhone with three real subscriptions ($N/yr).** Wave 6B-Prep-3 complete: HEAD `5790167`, **481 tests**. Remaining before 6B: **6B-Prep-4** (four small items, §8) plus the manual gates.
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

**⚠ The wire format is the `Exported*` types, and nothing else** *(added v2.4)*. Wave 9A's sweep found a latent second instance of the epoch problem: **the domain models' own `Codable` conformance** (`Subscription`, `TrialTerm`, and siblings) encodes `Date` with whatever strategy the encoder happens to carry — so a default `JSONEncoder` reaching any wire brings Apple's 2001 epoch straight back. Test-only today.

> **Only the `Exported*` types may cross a wire.** Domain `Codable` conformance is for tests and in-process use; if it ever needs to serialize outward, that is a signal to add an `Exported*` type rather than reuse it.

**Enforcement, and its honest limit** *(v2.5)*. A SwiftLint rule (`wire_coder_outside_export`) makes it an error for any production source outside `OttoDomain/Export/` to name `JSONEncoder`, `JSONDecoder`, `PropertyListEncoder/Decoder`, `JSONSerialization` or `NSKeyedArchiver`. Tests are exempt by design — *"domain `Codable` is for tests and in-process use"* is precisely that boundary.

**It is a tripwire, not a proof.** A regex cannot catch an aliased coder (`typealias E = JSONEncoder`), a third-party serializer, or anything constructed reflectively. Same power class as the `storedStatus` and `readingRepaired` rules — all three raise the cost of the mistake without making it impossible, and **recording that limit here matters more than the rule does**, because a rule mistaken for a guarantee is worse than no rule.

**⚠ The freeze applies to the main synced schema (V3) only** *(clarified in v2.5)*. The device-state store (§5.3) is outside the migration plan, never synced, and evolves additively — SwiftData lightweight-migrates it locally at next launch, so there is no migration cost to freeze against. v2.4's constraint said "the schema is frozen" without saying which, and Wave 6B-Prep-3 had to interpret it. It interpreted correctly and **flagged the judgment rather than burying it**, which is the behaviour worth keeping.

This is the same *one-mechanism-two-authorities* shape flagged five times already, and the same lesson as the watermark: **a representation that is device-local by convention will eventually leave the device.**

**Export format version policy** *(added v1.8 — Wave 8 correctly noted the spec never stated one)*:

> **Any field change bumps the format version, additive changes included.** Importing a *newer* version than the app understands **fails clearly**; importing an *older* one is supported, with documented defaults for fields that did not exist.

Additive changes bump it because `Codable` **silently drops unknown keys** — which would mean a newer export restoring into an older app loses data with no error anywhere. That is this application's forbidden failure mode, stated in §1: silent loss is the thing Otto exists to prevent, and it must not be the thing Otto does.

**Settings are device-local and excluded from the export.** They describe how this device behaves, not what the user owns — the same reasoning as the watermark (§5.3).

**A dangling `paymentMethodID` is a valid state, not an error** — under CloudKit sync a subscription can legitimately arrive before its payment method. It renders as *"Unknown payment method"* and resolves silently when the record arrives. It must never block display or throw.

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
| `pausedOn` | CalendarDay? | ⭐ **Added v1.7.** §7.2's frozen-price rule for paused spend has been **uncomputable since v1.1** — it specified pricing at the moment the pause began and no field recorded when that was. Six versions of a formula with no way to evaluate it. Legacy paused rows fall back to the current price |
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

**Mitigation:** when the entered date is the last day of a month shorter than 31 days, the Add screen must ask one question — *"Is this the last day of the month, or specifically the 28th?"* — and set the anchor to 31 or 28 accordingly. **⚠ v1.2 oversold this and the claim is corrected here:** a two-option prompt cannot recover a 29- or 30-anchored subscription from a Feb 28 entry — those remain unrecoverable, as does any anchor clamping has erased. What the prompt fixes is the *common* case, 28 versus 31. Erring early still holds as the safe direction; the inaccuracy is reduced, not removed.

**On `.paused`.** A paused subscription is one the vendor has suspended billing on but the user has not cancelled — a gym freeze, a seasonal hold, a plan on hiatus. It is a distinct state, not a flavour of cancelled, and it has three specific behaviours:

- **No `BillingEvent` rows are generated while paused**, and no renewal reminders fire.
- **It still counts toward the subscription list but not toward monthly burn** — Insights must show paused spend as a separate line, or the burn figure lies. **Formula (pinned in v1.1, was previously undefined):** paused spend uses the **monthly-equivalent at the price frozen when the pause began**, and a `PriceChange` recorded during a pause does **not** take effect until the subscription resumes. Without pinning this, Wave 7's numbers are arbitrary.
- **An optional `pauseEndsOn: CalendarDay?`** schedules a resume reminder. Un-paused-by-accident is a real failure mode: the vendor resumes billing on schedule and the user has stopped watching.

*(Added Aug 6 after a competitive scan — every shipping tracker in the category models paused as a first-class state, and retrofitting it once the `BillingEvent` ledger has history is materially harder than including it now.)*

### 4a. Sync-safety principles *(added v2.0 — from the Wave 6A readiness audit)*

The audit's central finding is that **several contracts that are true for a single device are false under per-record sync**, and each failure is silent. These are stated as principles because the individual bugs are instances of them:

**1. Absence is not deletion.** The aggregate save path soft-deletes any stored child (pause episode, evidence note, trial) missing from the in-memory array, on the contract that *"absence is deliberate removal."* Under per-record sync **that contract is simply false**: device A saving a stale snapshot tombstones device B's just-synced episode, with no error anywhere. **Deletion must be an explicit operation on an identified record**, never inferred from a collection's contents. This is the single most severe item found before 6B.

**2a. All convergence rules resolve to the *earliest* record, merging the losers** *(unified in v2.1)*. Wave 6B-Prep flagged that repair rules pointed in opposite directions — pause repair kept the **earliest** episode, cancellation reconciliation kept the **newest**. Both were defensible in isolation and the asymmetry was undocumented, which is how a future reader gets it wrong.

> **One shape for all three:** keep the record with the earliest start, **merge the losers' child records and state into it**, then tombstone them.

The ledger reconciliation rule already worked this way, so unifying makes all three consistent. The tie-break is *earliest* rather than newest because it matches the real-world fact in every case — the earliest pause is the one actually in effect, and the earliest cancellation is when the user actually acted. It is also the **safer direction for a verification product**: an earlier cancellation produces an earlier check date, so the error is watching sooner and possibly twice, never watching too late. Freshest parameters are not lost, because merging carries them.

**⚠ Closure clamps; a closed episode may never end before it starts.** "Closed at the winner's start" can produce a negative duration when the loser started later. Harmless today — nothing reads closed-episode durations — and guaranteed to surface the moment any feature computes pause spans. **An episode closed at a point before its own start is closed at its start**, giving zero duration, which honestly records "recorded, never actually in effect."

**2. Invariants are enforced at write and repaired at read — never thrown at read.** Two devices pausing independently produces two open pause episodes, and the at-most-one-open invariant then **throws in mapping, making the subscription unreadable on every device**, permanently, with no repair flow. Under sync, any invariant reachable from two devices *will* be violated eventually. **Reading must degrade and repair; it must not fail.** *(Same lesson as v1.9's backup bug, generalised: an invariant that throws at read time converts a sync artifact into a dead record.)*

**2b. A write path must never borrow the read path's tolerance** *(added v2.1)*. `readingRepaired` is **permissive by design** — its entire job is to never fail. Wave 6B-Prep found the edit path constructing through it, for a real reason: editing a degraded record has to re-describe the degraded shape without trapping. But a write path inheriting read-path permissiveness means **a future change to the repair rules silently changes write validation**, and that is the same one-mechanism-two-authorities smell as the retired `anchorDay` and the domain-side watermark.

> **A dedicated "describing" constructor**, whose tolerance is scoped to exactly the degraded shapes the edit form can legitimately hold, and which rejects everything else.

*(This is the fourth time the "something feels wrong and I can't say why" instinct has been correct. It is now the most reliable single signal in this project's review loop.)*

**3. A guard pinned to a version silently stops guarding.** The Wave 2 CloudKit-compatibility assertion **stayed green while asserting `OttoSchemaV2` after V3 became real** — checking nothing, reporting success. Guards must fail when the thing they guard changes: assert the current schema *and* count the models, so adding one without updating the guard breaks the build.

---

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

### 5.0a One id, one record — **the merge violates it on purpose** *(added v2.2)*

Wave 6B-Prep-2's fifth "can't fully articulate" flag: the rival-cancellation merge gives the winner **live copies** of the losers' evidence notes while each tombstoned loser keeps its own — so **one note id names records under two parents.** The report established it is deterministic, idempotent, lossless, and identical across both applier paths, and could not name the feature it breaks.

**The feature is 6B.** CloudKit addresses records by name, and the SwiftData mirror derives that name from the record's identifier. **Two live records sharing an id is not a smell there — it is a collision**, in the exact subsystem being enabled next. The candidates the report listed (a global fetch-note-by-id, a note-level dedup pass) don't exist yet; **the one that does exist is the one about to be turned on.**

> **Reparent, don't copy.** The losers' evidence notes are **moved** to the winner — one record, one id, one parent — and the loser is then tombstoned holding none.

Losslessness is preserved, since the notes end up exactly where they are wanted, and §5.0's premise survives intact. *Fifth consecutive time the instinct was right, and the first time it named a hazard whose consequence was concrete rather than latent.*

---

### 5.2a Trial conversion — **the founding failure, reproduced in the design** *(added v1.3)*

**⚠ This is the most serious defect found in the spec so far, and it was found in Wave 3, three waves after the founding story was written down.**

v1.2 said a `.trial` subscription materializes exactly one `BillingEvent`, at `conversionDate`. It never said **who moves the status from `.trial` to `.active`, or when.** Follow it literally: the user ignores the trial — *which is the founding failure mode* — the status stays `.trial` forever, the one conversion row sits there, and **no subsequent charge is ever materialized or reminded about**, because `.trial` materializes nothing else and `.active` was never set.

That is the FoodApp case: months of silent charges, and Otto silent alongside them.

**And the near-miss is worse than the bug.** The obvious fix is to have Wave 5's trial flow perform the transition when the user acts on a notification. **A transition that requires a tap recreates the original failure exactly**, because the founding scenario *is* the user not tapping. Any design where correct behaviour depends on the user's attention has misunderstood the product.

#### The rule: conversion is **derived**, never awaited

**`effectiveStatus(asOf:)` is a pure domain function, and it is what every consumer uses** — the materializer, the reminder planner, the Today classifier, Insights. The stored `status` records how the subscription *began*; the effective status is computed.

> If stored status is `.trial` and `today >= trialTerm.conversionDate`, the effective status is `.active`.

On conversion, the paid sequence takes over: **anchor becomes `conversionDate`, amount becomes `convertsToAmountCents`**, and the cycle runs from there. No flag, no job, no tap. A trial that converts while the phone is in a drawer for six weeks still materializes its charges and still generates reminders the moment anything asks.

**Persistence is an optimisation, not the mechanism.** When the app next runs and observes a converted trial, it may write the status through and record the price transition — but **no behaviour may depend on that write having happened.** If it does, the six-weeks-in-a-drawer case fails again.

#### Pause resume is derived too — **the founding scenario's fourth escape route** *(added v1.6)*

A pause with a known end date is structurally identical to a trial with a known conversion date, and it had the identical bug. Wave 5.5 found that **the materialization watermark advances while a subscription is paused**, so:

> Subscription paused with `pauseEndsOn` = Sep 1. The user doesn't open Otto until Oct 15. The vendor resumed billing on schedule and charged on Sep 1 and Oct 1. Otto's status is still `.paused`, so nothing materialized — and the watermark has moved past both dates, so a manual resume **cannot backfill them.** Two real charges, permanently invisible.

**This is the fourth distinct mechanism** through which "the user wasn't looking" has produced silent failure — after status derivation (v1.3), the notification ladder (v1.4), and the ledger window (v1.5). The fix is the §5.2a pattern applied where it was missed:

| Case | Rule |
|---|---|
| `pauseEndsOn` **set** | `effectiveStatus(asOf:)` treats a paused subscription past `pauseEndsOn` as **`.active`**. The resume is **derived, never awaited** — exactly like trial conversion. Materialization then proceeds from `pauseEndsOn` with no backfill needed |
| `pauseEndsOn` **nil** (indefinite) | There is no derivable resume date, so **the watermark must not advance while paused.** It freezes at the pause, and a manual resume backfills from it |

**The generalization, now stated as a design rule:** *any state whose exit is a known future date must exit by derivation.* Trials, pauses, and anything added later. A state that waits to be told it has ended will eventually not be told.

#### ⚠ Stored status is not readable outside the persistence layer *(added v1.7)*

Wave 7 flagged that `caughtUpCancellationRecords` filters by **stored** status — noting it is *correct today*, but that it is "the stored-vs-effective read pattern that produced the Wave 4 bug."

**That flag is the right instinct and the rule is now structural.** A dangerous pattern that happens to be correct today is a defect waiting for an unrelated future change to activate it, and it will activate silently — which is this project's characteristic failure mode.

> **Every status read outside the persistence and mapping layers goes through `effectiveStatus(asOf:)`.** Direct reads of the stored `status` property are prohibited above layer 2 and should be prevented by a lint rule or by access control rather than by reviewer attention.

#### ⚠ Derive before you mutate *(added v1.5, after this exact bug shipped in Wave 4)*

Wave 4's `startCancelling` flipped the status **before** computing the verification check date. Because `billingAnchor(asOf:)` keys off the stored status, a converted-but-unflipped trial cancelled after conversion computed its watch date from the **trial-start** anchor rather than the **conversion** anchor.

Concretely: a trial starting Jul 1, converting Jul 31, monthly, cancelled Aug 5 would have watched **Sep 1 instead of Aug 31** — the app's differentiating feature, pointed at the wrong day, in the flow it exists for.

> **Any operation that both mutates status and derives from status must derive first, then mutate.** Where practical, derive from data that survives the mutation — the fix here reads the trial *term*, which the status overwrite cannot destroy.

The derived-status design in §5.2a is correct and is not what failed. **What failed was ordering inside a single operation** — which is a category of bug that pure functions cannot prevent, because both the read and the write are individually correct.

#### Two consequences

- **Otto must announce the conversion.** A notification on `conversionDate`: *"Your FoodApp trial converted today. You're now being charged $11/month."* Not a reminder to act — a statement of fact about money that started moving. Wave 4 owns it; it is P1.
- **A converted-but-never-acknowledged trial is a Today *Needs action* item**, and stays one until the user confirms they know. This is the case the app exists for; it does not get to scroll away.

---

### 5.2b Model invariants *(added v1.3)*

Three states are representable in the types but meaningless in the domain. Each was silently no-op'd somewhere in Wave 3 — and **silent no-ops in separate switch arms are how two code paths eventually disagree.** Each is now a declared invariant, enforced at construction and surfaced loudly, never skipped quietly.

**⚠ Status-coupled invariants apply to LIVE records only** *(added v1.9)*. Wave 8.5 caught its own newly-introduced bug in self-review: deleting a paused subscription tombstones its episodes, after which the *"a paused subscription must have an open pause episode"* check refused the row — making a **full backup fail because a deleted gym membership existed.** An invariant enforced against tombstones turns ordinary history into a permanent export failure. Tombstones are outside every status-coupled invariant, with a regression test on the export path. **v2.0 generalises this** — see §4a principle 2: invariants are enforced at write and **repaired** at read, never thrown at read.

**⚠ "Loudly" needs a definition, added in v1.4.** The established read policy is skip-with-log, which is loud *in the console* and invisible *in the UI* — the opposite of how §7.1 treats the cancelled-without-record invariant, and it means an unmappable `.trial` record simply vanishes from the user's view. For a product whose whole promise is that nothing slips past unnoticed, a subscription disappearing silently is the worst available failure.

> **Unmappable records are surfaced as a single aggregate card** in Today's *needs review* — *"2 subscriptions couldn't be read"* — not one card per record.

Aggregate rather than per-record because **Wave 6 will make partially-synced records routine**: CloudKit delivers records mid-sync that are legitimately incomplete for a moment, and a per-record surface would turn normal sync into an alarm. What the count must never do is stay at zero while records are missing. Revisit the threshold in Wave 6, once real sync behaviour is observable rather than guessed at.


| Invariant | Why |
|---|---|
| A `TrialTerm` on a **non-`.trial`** subscription is **history, not a toggle** — never derived from, never rebuilt from, and never deleted by an edit *(added v1.5)* | Wave 5 found Add/Edit deriving its trial toggle from `status == .trial`, so **editing the price of a confirmed-converted subscription silently rebuilt it with `trial: nil`** — destroying exactly the *"converted and noticed late"* record that §7.3's zombie report depends on |
| A `.trial` subscription **must** have a `TrialTerm` | Without one there is no `conversionDate`, so §5.2a cannot compute anything. Wave 3 found three separate sites no-op'ing on this |
| A `.cancelled` or `.cancellationPending` subscription **must** have a `CancellationRecord` | Otherwise it is unwatched, which is Failure B with extra steps |
| `cycleStartDay` is **never mutated in place** | See below |

**On `cycleStartDay` immutability — the reading Wave 3 asked for is the correct one.** The rule means *no in-place mutation, ever*: no traversal, computation, or clamp may write back to it. It does **not** forbid a user correcting a wrong entry on the Edit screen, which constructs a new value. A correction is not drift. The distinction that matters is *who* changes it — the user deliberately, never the code incidentally.

---

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
| `acknowledgedAt` | Date? | ⭐ **Added v1.4.** §6.4's *"Keeping it"* and §6.3's *"remainder is cancelled on acknowledgement"* both named a state that did not exist, so neither could actually hold: rescheduling is cancel-all-then-replan, which **replans the silenced reminders right back in the same cycle.** Written by the action handler; the planner skips reminders for acknowledged events. **Must land before Wave 6 while it is still a field addition** |
| `actualAmountCents` | Int? | if it differed → triggers a price-change prompt |

**When rows are created (specified in v1.1 — previously undefined, and a Wave 2 blocker).** Future billing dates are a **pure function of the anchor and the cycle**, so storing them in advance duplicates derived state and grows the table without bound.

**Rule: a `BillingEvent` is materialized at the moment its reminder is scheduled, and never earlier.** Concretely — the reminder scheduler runs, computes the events inside the rolling ~90-day horizon, and creates any that don't yet exist. Rows past the horizon do not exist; the UI derives those dates on the fly.

**Which window governs — the reminder's, not the charge's** *(pinned in v1.2; v1.1 left the two unreconciled)*. A reminder fires `reminderLeadDays` *before* its charge, so a reminder inside the horizon can belong to a charge that falls just outside it. Since the entire reason a row exists is to carry that reminder's state, **the row must exist whenever the reminder does.**

> Materialize every charge date in `[lastMaterializedThrough, today + horizonDays + maxReminderLeadDays]`.

**⚠ The window must reach backwards, and v1.4's did not** *(fixed in v1.5 — the third time the founding scenario has slipped through a different mechanism)*. v1.4 materialized from `today` forward. **A trial that converts while the app is closed has its conversion date behind `today` by the time any pass runs** — so the single most important charge in the product never gets a ledger row, and therefore gets no verification and no price-mismatch coverage, in precisely the phone-in-a-drawer case the app exists for.

**Rule: `Subscription.lastMaterializedThrough: CalendarDay` is a watermark**, initialised to the anchor (or `createdAt`, whichever is later) and advanced only after a successful pass. Every charge date between the watermark and the horizon materializes, so **no charge date can pass unobserved between scheduler runs**, however long the gap.

The watermark also bounds the work: a Mode B subscription entered today does not backfill years of history it never had rows for, because the watermark starts at entry.

**⚠ An absent watermark is a hazard, not a neutral default** *(corrected in v2.0)*. It was previously described — including in the Wave 6A prompt — as meaning "re-materialize from the anchor: safe but wasteful." **That is wrong, and the code was right.** A nil watermark materializes **from today**, skipping the entire unobserved window. That is not waste; **it is the founding hazard**, silently. This is why the migration *refuses* rather than degrading when it cannot carry watermarks across. A watermark is initialised to the anchor or `createdAt`, **never to today**, and there is no safe fallback for a missing one.

**The watermark is device-local and is NOT synced** *(decided in v1.6; Wave 5.5 correctly flagged that its merge behaviour was undefined)*. It records *what this device has done*, not anything about the subscription — so it is stored outside the CloudKit-backed schema, per device.

**How, concretely** *(specified in v1.7 — Wave 7 correctly noted the watermark still physically lives on `StoredSubscription`, and SwiftData cannot exclude a single property from CloudKit sync)*:

> **A second, local-only `ModelConfiguration` holds device-scoped bookkeeping.** The watermark is its first inhabitant and almost certainly not its last — anything that describes *this device's progress* rather than *the user's data* belongs there.

**⚠ This relocation is a PRECONDITION for Wave 6, not its first step** *(escalated in v1.9)*. The Wave 8.5 sweep named it the thing it would most regret freezing, with an exact reading of the risk: *everything depends on "first schema act" actually being first, and if CloudKit ever turns on with the watermark still on `StoredSubscription`, the advanced-watermark hazard becomes real silent loss — the precise failure this app exists to prevent.*

That is correct, and it is also the shape of failure this project has hit repeatedly: **a plan that depends on a future wave's discipline holding.** So the plan is retired. Wave 6 is split — **6A relocates the watermark with CloudKit still off and stops; 6B enables CloudKit** — so that "the watermark moved first" is a *verified committed state* rather than an intention.

Wave 8's export already excludes it, since exporting one device's progress marker into a file destined for another device is meaningless at best.

**Backwards edits rewind the watermark** *(added v1.7)*. A pause set to end Dec 1 that the user later corrects to Sep 1 leaves the Sep–Nov charges stranded behind an already-advanced watermark. Generalized, because this is the same shape as §5.3's invalidation rule rather than a pause-specific quirk:

> **Any edit that moves a subscription's billing sequence earlier must rewind the watermark to the earliest affected date.**

The reasoning is that last-write-wins is the wrong merge for it in a dangerous direction. A **regressed** watermark is harmless: re-materialization is idempotent and dedups on `(subscriptionID, expectedDate)`, so the cost is wasted work. An **advanced** watermark is not: if device A's watermark syncs ahead of the rows it corresponds to, device B skips charge dates that were never materialized anywhere. Since CloudKit cannot express "merge by taking the minimum," the safe move is not to sync it at all. Each device materializes independently.

**⚠ "The dedup makes the duplication invisible" was wrong** *(corrected in v2.0)*. The `(subscriptionID, expectedDate)` uniqueness check only **prevents** a duplicate at write time; it never **reconciles** one that arrives later. Two devices materializing the same charge date concurrently — which is the normal case once sync is on, since materialization is deliberately per-device — produce **permanently duplicated ledger rows**, each with its own independent acknowledgement and confirmation state.

> **A post-sync reconciliation pass is required**: for each `(subscriptionID, expectedDate)` group, keep the row with the earliest `createdAt`, **merge** the acknowledgement and confirmation state from the rest (any acknowledgement counts, any confirmation counts), and tombstone the losers. Deterministic, so every device reaches the same result without coordination.

**Watermarks after a replace-import** *(resolved in v2.1)*. Wave 6B-Prep flagged a genuine contradiction: v2.0 says a nil watermark is the founding hazard with **no safe fallback**, yet replace-import deliberately nils every watermark — so the next pass observes from today and skips the window. The export correctly carries no watermark, so there is nothing to restore from. **But there is:**

> **Reconstruct each watermark from the imported ledger** — the latest **live** `expectedDate` among that subscription's imported rows (tombstoned rows are invalidation artifacts; excluding them only pulls the watermark *earlier*, which is the safe direction). Where a subscription has no imported rows, fall back to its **anchor**, never to today.

**⚠ The crash window changed sides, and the new side is worse** *(v2.2 — caused by the v2.1 fix above)*. A crash between restore's two saves used to leave watermarks **nil**; it now leaves the **pre-import** watermarks, which can sit **ahead** of the imported ledger — vouching for rows the restored database does not have. **That is the one direction this whole design refuses**, and it is invisible where nil was merely known-bad.

> **Restore writes a dirty flag before it begins.** A dirty flag forces watermark reconstruction from the ledger and clears itself.

**"On launch" is implemented as "before any watermark access"** *(recorded in v2.5 so a future reader does not "fix" it back)*. The heal is guarded at the watermark accessors rather than at app launch, so **there is no code path to a stale-ahead watermark regardless of who reads first after a crash.** Strictly stronger than the spec's original wording and requiring no app-layer wiring — the equivalence is recorded here precisely because it *looks* like a deviation.

**⚠ The heal takes the minimum of current and reconstructed** *(added v2.5 — Wave 6B-Prep-3 correctly flagged that "both branches land safe" overclaimed)*. There is a residual double fault: flag written → main save fails (nothing persisted) → the flag *retraction* also fails → the next watermark access reconstructs over a ledger that was never replaced. Against an untouched ledger, reconstruction can **advance** a deliberately rewound watermark (the backwards-edit rule above) past its stranded gap. Two consecutive device-store save failures is vanishingly narrow, but **it is the one path where the heal itself points the wrong direction.**

Taking the minimum deviates from v2.1's literal definition of reconstruction. That is the correct trade: **the principle the definition serves is that watermarks err earlier, never later**, and v2.1's wording was written before this case was known. Where a definition and the principle behind it disagree, the principle wins.

This is better than either option the report offered: rather than choosing between *hazardous-but-known* (nil) and *hazardous-and-invisible* (stale-ahead), the crash window becomes **self-healing**, reusing the reconstruction mechanism that already exists. **A fix that moves a hazard rather than removing it is worth re-examining** — this one did, and only landed because the report said so plainly.

Both branches land on the safe side: re-materializing from the anchor is wasteful and harmless, while observing from today is the founding hazard. The contradiction was real and the fix removes it rather than documenting around it.

Prevention alone is only sufficient in a single-writer world, which is exactly what enabling sync stops being.

Corollary: watermark writes are bookkeeping, not user edits, and **must not bump `updatedAt`** — doing so would make every scheduler pass look like a user modification to conflict resolution.

*Noted for the pattern file:* §5.2a fixed the founding scenario in **status derivation**, v1.5 fixes it in the **ledger**. Each fix was correct and each left a different mechanism through which the same failure could recur. **Every new subsystem should be tested against the phone-in-a-drawer case explicitly**, not assumed to inherit the property.

The charge window is therefore slightly wider than the reminder horizon, by the largest lead time in use. Deriving it from the charge window instead leaves the outermost reminders with no row to attach to.

**Which statuses materialize** *(unspecified in v1.1)*:

| Status | Materializes? | Why |
|---|---|---|
| `.active` | ✅ Yes | The ordinary case |
| `.trial` | ✅ **Exactly one**, at `conversionDate`, for `convertsToAmountCents` | ⭐ **Otherwise the single most important charge in the app has no ledger row.** The trial conversion is the charge Otto exists to catch; without a row, neither verification nor price-mismatch detection covers it |
| `.paused` | ❌ No | §5.1 — no charges while paused |
| `.cancellationPending` / `.cancelled` | ❌ Not prospectively | A `BillingEvent` asserts a charge is *expected*, which is the opposite of what the record claims. These are watched by §5.4 verification instead |
| `.archived` | ❌ No | Terminal |

**When a schedule change invalidates existing rows** *(added v1.3; v1.2 said when rows are created but never when they stop being valid)*. Editing a subscription's anchor, cycle, or amount changes the sequence — but `.upcoming` rows for the *old* sequence remain in the ledger, and date-based dedup will not remove them, so the user sees phantom charges on dates that will never happen.

> **On save with a changed anchor, cycle, or amount: soft-delete every `.upcoming` row that no longer matches the new sequence, then re-materialize.**

Rows in any other state are **never** touched — a confirmed charge is history and history does not change because a schedule did.

**Invalidation never touches past-dated rows either** *(added v1.8)*. Wave 8 found that a price edit tombstones **every** `.upcoming` row at the old amount — past-dated ones included — and nothing reaches back to recreate them. The result is that a charge date which passed without the user confirming it **silently disappears from the ledger** the moment they update the price.

> **Only future-dated `.upcoming` rows are invalidated. A past-dated row is history, whether or not it was ever acknowledged.**

The reasoning is that an unacknowledged past row is not a mistake to be cleaned up — it is a record of what was expected on a date that has already happened, and the new price applies going forward, not retroactively. Where a past row is genuinely wrong (a mis-entered start date), **the user deletes it from the ledger themselves.** Otto surfaces the discrepancy; it does not decide the history was wrong — the same boundary as everywhere else in this document.

**Generalized in v1.4: status transitions invalidate too.** v1.3 scoped this to anchor, cycle, and amount edits, which left a hole — pausing or archiving a subscription leaves its future `.upcoming` rows sitting in the ledger, and the user sees phantom charges in Detail for a subscription that is not going to charge them.

> Invalidation triggers on **any change that alters the expected sequence**, including transitions into `.paused`, `.cancellationPending`, `.cancelled`, and `.archived`. Resuming from `.paused` re-materializes.

**Which tombstones block re-materialization** *(pinned in v1.4)*. Wave 3's dedup blocked re-creation on *any* tombstoned date, which §5.3's "new records rather than resurrections" language quietly overruled. The two kinds of tombstone mean different things:

| Tombstoned row | Blocks re-materialization? |
|---|---|
| `.upcoming` | ❌ **No** — it is an invalidation artifact, the byproduct of a schedule change. Blocking on it would prevent the corrected sequence from ever materializing |
| Any other state | ✅ **Yes** — deliberate removal of history, and re-creating it would resurrect what the user removed |

**The one retrospective creation path.** When a verification reports `.stillCharging`, that charge **did** happen and needs a ledger row — created at that moment with state `.unexpectedCharge`. This is the **only** producer of that state; in v1.1 the enum case existed with nothing able to create it.

The justification is that a row only earns storage once there is **user-facing state to attach to it** — a reminder that fired, a confirmation, an amount mismatch. Before that it is a calculation, not a record. This also caps the ledger's growth at roughly `subscriptions × cyclesPerQuarter` new rows per scheduling pass.

### 5.3a Episode tables — **one-to-one where reality is one-to-many** *(added v1.8)*

Wave 8 surfaced two findings that look unrelated and are the same modelling error:

- **`§5.4` has no un-cancel.** Every exit from `.cancellationPending` leads to archived or still-charging, so an accidental *"I'm cancelling"* tap is **irreversible in-app** — and because storage holds exactly one cancellation, any un-cancel design added later would overwrite the first record's history.
- **Resume erases pause history.** `pausedOn` and `pauseEndsOn` are cleared on resume, which is fine for §7.2's current-burn figure and makes *"what did this cost me last year"* permanently unanswerable.

**Both are one-to-one relationships modelling something that recurs.** A subscription can be cancelled, resubscribed, and cancelled again; it can be paused every winter. That is ordinary life, not error correction — the one-to-one shape was always going to be wrong, and it happens to be the single change class that **cannot** be made cheaply after Wave 6, because relationship cardinality is a migration rather than a field addition.

> **`CancellationEpisode` and `PauseEpisode` are one-to-many histories**, each carrying the §5.0 quartet plus its own start, end, and outcome. The *current* episode is the one with no end date. Un-cancel closes the open cancellation episode with an `.abandoned` outcome rather than deleting it.

**Nothing is ever cleared on exit from a state.** Exiting writes an end date.

*Worth recording as a review question rather than a one-off fix:* **two instances of this error appeared in a single report, in the last wave where fixing them was cheap.** Wave 8.5's schema-freeze pass exists to sweep for the rest — the question being *"which of these one-to-one relationships model something that can happen twice?"*

---

### 5.4 `CancellationRecord` — the Failure-B fix

| Field | Type |
|---|---|
| `subscriptionID` | UUID |
| `markedCancelledAt` | Date | UTC instant — records *when the user acted*, and is **never** used for date arithmetic (see below) |
| `nextChargeDateIfNotCancelled` | CalendarDay**?** | **Renamed and made required in v1.1; made conditionally optional in v1.7.** ⚠ The v1.1 reasoning still stands — an *unknown* date must never be papered over with a runtime fallback. But §5.4's indefinite-pause path creates a state where the date is **legitimately, knowably absent**, which is a different thing. **Invariant: `nil` if and only if `verificationState == .awaitingResumeDate`.** Enforced, not assumed — an optional without that constraint would reopen exactly the hole v1.1 closed |
| `verificationState` | ... `.awaitingResumeDate` | **Added v1.7** — generates no notifications, refuses verification answers (there is no unverified assertion to confirm), and surfaces in Today's *Needs action* asking for the resume date. Supplying it starts the ordinary watch |
| `expectedChargeAmountCents` | Int**?** | ⭐ **Added v1.5; corrected to optional in v1.6.** Wave 5.5 was right that there is no honest non-optional default for a record whose amount was never captured — **`nil` means "legacy record predating v1.5,"** and a fabricated zero would be worse than an absence in a document destined for a bank. The roll-forward backfills it where it can. The date is stored at cancellation because it is unrecoverable afterwards — **the amount has exactly the same property and was not stored**, leaving the dispute summary to infer it heuristically (by checking whether the anchor equals the conversion date). Correct for every flow-produced state, defeatable by a hand-edited price. **The dispute summary is the deliverable that ends at a bank; nothing in it should be a heuristic.** Computed once, at cancellation, like the date |
| `verificationState` | `.pending` `.stillCharging` `.needsManualReview` `.awaitingResumeDate` — **live states only; `.verifiedStopped` removed in v1.9** |
| `unansweredCheckCount` | Int, default 0 | **Added v1.3** — §5.4's three-cycle cap needs somewhere to count. Wave 5 lands before CloudKit, so this is still a field addition rather than a migration |
| `verifiedAt` | Date? |
| `evidenceNotes` | **[EvidenceNote]** | ⭐ **Made a list in v1.9.** Wave 8.5 noted this is *"one field where a long cancellation fight produces many artifacts"* — a call, then an email, then a chargeback filing, each with its own date. **That is the same one-to-one-for-something-recurring error §5.3a was written to eliminate**, and it is cheap now for exactly one more wave. Each note carries its own timestamp and text |

**Why that field is now required, and renamed (v1.1).** As originally written it was optional, and the fallback was "the next billing date after today." That fallback is unimplementable in the domain layer: `markedCancelledAt` is a UTC instant, and §4.1 forbids converting an instant to a calendar day without a timezone — so the domain cannot derive the check date at all, and any runtime fallback drifts later every day the app goes unopened. **The date is fully computable at cancellation time** from the immutable anchor and the cycle, so it is computed once, then, and stored.

The rename matters too: *"expected final charge"* is ambiguous — some vendors bill once more, most don't. The field's actual job is to name **the date a charge would land if the cancellation silently failed**, which is exactly the verification trigger. `nextChargeDateIfNotCancelled` says that.

⛔ **The selector: the first occurrence STRICTLY AFTER the cancellation day** *(Wave 10, defect G — the predicate was effectively `first occurrence ≥ today`)*. The cancellation day is `markedCancelledAt` converted to a calendar day in an explicit timezone by the caller, per §4.1 — the domain receives the day, never the instant. Any occurrence **on or before** the cancellation day has already landed legitimately, so the single strict inequality handles every case: cancel on the conversion day → watch the next cycle (the device run watched the conversion charge itself, so *both* verification answers were meaningless — "yes, it stopped" would have archived on a check with no evidential content, §5.4's false-confidence failure by another route — and the dispute summary read "cancelled Aug 10 / charged Aug 10," which a bank rejects on sight); cancel mid-cycle → next occurrence; cancel during a trial before conversion → the conversion charge, correctly, since it is the first charge that lands if the cancellation failed. It also ends the double-count: the same charge can no longer appear as both `Expected` and `Unexpected` ledger rows, because the watched date can never be an already-landed one.

**Generalization, worth carrying:** `>= today` is an unsafe default anywhere a past occurrence can be a legitimate already-settled event. Wave 4's *derive before you mutate* protects the **read** — compute from data the mutation cannot destroy; it says nothing about **which element** of a correct sequence you pick. Defect G derived at the right time, from the right sequence, and picked the wrong element. Both rules now hold; neither replaces the other.

**Cancelling a *paused* subscription** *(specified in v1.5; §5.4 and §5.1 did not compose)*. The check date comes from the anchor sequence, which ignores `pauseEndsOn` — so the verification could fire on a date the vendor would never have charged, and a "no charge arrived" answer would prove nothing.

- **`pauseEndsOn` set:** the next would-be charge is the first billing occurrence **on or after `pauseEndsOn`** — composed, since Wave 10, with defect G's rule: **and strictly after the cancellation day**. (While a subscription is effectively paused the cancellation day precedes `pauseEndsOn`, so the composition is a structural guard rather than a behavior change — it exists so no future path through this branch can watch an already-landed charge.)
- **`pauseEndsOn` nil** (indefinite pause): there is no determinate date. **Do not guess** — defer the check and surface the subscription in *needs review* so the user supplies a resume date. A verification answered against a fabricated date is worse than no verification, because it produces false confidence in exactly the place the product promises certainty.

**A cancelled subscription is not archived until verification passes.** It stays in a "Watching" state and the app checks back on the next date a charge would have landed. If the user reports a charge did arrive, the record flips to `.stillCharging` and the app surfaces everything needed for a dispute: cancellation date, confirmation note, the charge date and amount.

**When a verification check goes unanswered** *(specified in v1.2; v1.1 was silent, and §6.2's catch-up rule covers reminders-before-a-billing-date, not this)*. The user opens the app a week after the check date and the state is still `.pending`.

**Rule: keep watching, and roll the check forward to the next date a charge would have landed — but cap it at three consecutive unanswered cycles.** A cancellation that silently failed will charge again next cycle, so one ignored notification must not end the watch. But past three, the signal is that notifications aren't reaching this item, and a fourth won't either: the subscription moves to a **persistent card in Today's *Needs action* section** and stops generating notifications. Escalating in the app rather than escalating the notifications is the correct response to being ignored.

#### The `verificationState` / `outcome` folding *(resolved in v1.9)*

Wave 8.5 flagged this as the thing it *couldn't fully articulate*: the two enums "together feel one field too wide," with every combination pinned by invariants and no concrete failure visible. **Saying it anyway was correct — there is a folding, and it is the overlap.**

`.verifiedStopped` appeared in **both** enums, which is the whole smell. Once the distinction is stated the resolution is forced:

| Field | Meaning | When it applies |
|---|---|---|
| `verificationState` | Where the watch **is now** | While the episode is open (`endedAt == nil`) |
| `outcome` | **How the episode ended** | Once closed |

> **`.verifiedStopped` is removed from `verificationState`.** Reaching that result does not *set a state* — it **closes the episode**, with `outcome = .verifiedStopped`.

No overlap remains, "open" is exactly `endedAt == nil`, and no invariant is needed to forbid the nonsensical combinations because they are no longer representable. `.stillCharging` correctly stays live: a dispute in progress is an ongoing watch, and resolving it closes the episode the same way.

*Worth keeping as a working instruction:* **"tell me what feels wrong even if you can't say why" produced a real structural simplification here.** It is a different and more valuable question than "what is broken."

---

### 5.5 `PriceChange` and `PaymentMethod`

`PriceChange`: `id`, `subscriptionID`, `effectiveDate`, `oldAmountCents`, `newAmountCents`, `source` (`.userEdit` / `.chargeMismatch` / `.trialConversion` — the third added in v1.5, written when a trial's confirm flow appends the trial→paid price transition), `note`, plus the §5.0 quartet. *(v1.3: `recordedAt` **dropped** — it duplicated §5.0's `createdAt`. Two fields meaning almost the same thing is how they drift apart.)* Editing a price never overwrites history — it appends. This is what lets Insights show "Netflix has gone up 34% in three years."

`PaymentMethod`: `id`, `label` ("Bank Mastercard ••4821"), `last4`, `issuer`, `expiryMonth`, `expiryYear`, `isDefault`. Card-expiry warnings fall out of this for free, and the second user runs multiple cards so it earns its place in v1.

### 5.6 `Category` — fixed enum

Streaming & Video · Music & Audio · News & Reading · AI & Software Tools · Cloud & Storage · Gaming · Fitness & Health · Food & Delivery · Shopping & Memberships · Phone & Internet · Finance & Insurance · Education & Courses · Other

Fixed rather than free-form so the rollups mean something — free-form categories produce "AI", "ai tools", and "LLM" as three separate lines. `Other` plus a note field is the escape valve. Raw values are stable strings, never enum ordinals, so reordering the list later doesn't corrupt stored data.

---

## 6. The notification engine

### 6.1 The hard constraint

**iOS permits a maximum of 64 pending local notifications per app.** Anything scheduled beyond that is silently dropped. With trials taking three slots each, the ceiling arrives around twenty subscriptions — and the ones dropped are the furthest out, which are the annual renewals you most need warning about. Get this wrong and the app fails in exactly the way it exists to prevent, without any error appearing.

**Snoozes consume the same 64 slots** *(added v1.4 — v1.3's budget model did not contemplate them)*. A snoozed reminder is a pending request like any other. They live in a distinct identifier namespace (`snooze.<origin-kind>`) so that a cancel-all-then-replan cycle does not wipe them, and they are **not** replanned by the scheduler — which means the effective budget for planned reminders is `64 − pendingSnoozes`.

Snoozes rank **above P1**: the user explicitly asked for that one, and honouring an explicit request before an inferred schedule is the right ordering. The consequence — a user who snoozes heavily shrinks their own scheduling horizon — is acceptable and must be reflected in the horizon date Today displays.

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

Scheduling is **idempotent**: recompute the plan, then **reconcile it against the device's pending requests by diff** — remove only identifiers the plan no longer wants, add only identifiers the device does not hold, and add over the top where content differs, since the same identifier replaces.
Notification identifiers are deterministic — `"<subscriptionID>|<ISO date>|<kind>"` — so a double-run is a no-op, and **they must stay stable and content-derived**: an identifier that embeds anything minted per pass (a timestamp, "today") breaks both the replace semantics and the delivered-record check below.

⚠ **Never remove-all-then-re-add** *(Wave 10, defect B)*.
The v1.x cycle cancelled every pending request and re-added serially, which holds a window in which a suspension leaves the device with NOTHING pending — observed on a physical device at 5 ms from losing all three trial rungs, with no clock manipulation involved, on a product whose founding scenario is a phone sitting untouched in a drawer.
The diff makes the empty-device state **inexpressible**: at every instant the device holds a superset or the correct set (same move as v2.1 removing delete-on-absence rather than disabling it).
Triggers:

- App enters foreground
- Any subscription created, edited, or deleted
- A notification is delivered or acted on
- `BGAppRefreshTask` (registered for daily execution)
- `NSSystemTimeZoneDidChange` and significant-time-change notifications
- Notification permission newly granted

**Catch-up rule (added v1.1 — a real product bug, not a nicety; ⚠ implemented for the first time in Wave 10).** If a reminder's computed day is already in the past but its billing date is still in the future, **schedule it immediately** rather than skipping it. Without this, Mode B onboarding silently fails in its most common case: the user adds a subscription because they noticed a charge coming in two days, the default 3-day lead is already past, and **no reminder fires for the exact charge that prompted them to add it.**

⚠ **From v1.1 through v2.5 this rule had never worked, for anything.** The codebase contained zero `UNTimeIntervalNotificationTrigger`s; the planner's window filter silently discarded past trial rungs; and the scheduler dropped every same-day rung whose hour had passed, *with a comment claiming this rule would recover it* — the next run dropped it identically. The rule as now implemented (Wave 10, defect A):

- **Fire immediately** — a short interval trigger (5 s; a calendar trigger in the past never fires) — when a rung's fire instant has passed **and** the deadline it exists to protect is still ahead. This covers every kind: renewal leads, trial leads, the cancel-by-day rungs, pause-ending warnings, verification checks, and the conversion announcement on its own day.
- **Never fire when the deadline is behind.** Enforced in the *planner*, structurally: a trial whose conversion passed derives as active and plans no trial rungs at all, so a dead-deadline rung cannot reach the scheduler. A notification saying "cancel by today" about a dead deadline is the dishonesty v1.4 legislated against.
- **Never fire twice.** Before scheduling a catch-up, check `getDeliveredNotifications` for the same identifier — the system's own delivery record, never a stored flag a restore could desynchronize. For that check to mean anything across passes, **the rung keeps its ORIGINAL day in the plan**; re-dating it to "today" would mint a fresh identifier every day and re-warn daily until the deadline. Honest limit: a notification the user has cleared from Notification Center leaves the delivery record, so clearing plus a same-day reschedule can re-deliver once.
- **Budget:** catch-ups are ordinary plan members — they occupy real slots inside the `64 − pendingSnoozes` budget at their rung's own priority, and being dated earliest they win their priority band's nearest-first ordering. They inherit priority rather than jumping the queue: a late usage check-in must not evict a live trial rung, because lateness does not change what protects money. Snoozes still rank above everything (v1.4: an explicit user request outranks an inferred schedule).

**When the lead time is longer than the cycle** *(specified in v1.4)*. A 45-day lead on a monthly subscription puts several lead days in the past simultaneously, and identical `(day, kind)` pairs collide in the deterministic identifier scheme. **Emit exactly one catch-up: the earliest un-warned charge.** More than one is noise about charges the user will be reminded of again anyway.

Separately, this configuration is almost always a mistake rather than an intent — it means the user is permanently being warned about the charge *after* next. **Add/Edit should warn when `reminderLeadDays` ≥ the cycle length**, rather than silently accepting it.

### 6.3 The reminder ladders

**Renewal (ordinary):** one notification at `reminderLeadDays` before, plus an optional same-day one controlled by `sameDayReminder` (§5.1; the field was missing in v1.0 — the feature had no data model).

**Trial (aggressive — this is Failure A):**
1. At `reminderLeadDays` before `cancelByDate`
2. Morning of `cancelByDate` — **time-sensitive**
3. Evening of `cancelByDate` — **time-sensitive**
4. If still unacknowledged, repeat daily until the conversion date arrives
5. **On the conversion date, the §5.2a announcement *is* the notification** — the ladder's final rung, not a separate one

**Why the announcement owns conversion day** *(adopted in v1.4 from Wave 4's proposal)*. §6.3 had the dailies running "until the conversion date passes" while §5.2a put the announcement on that date — both claiming the same day. The announcement wins, for a reason that is about honesty rather than tidiness: **the cancel-by deadline has already passed by conversion day** (`cancelBy = conversion − buffer`), so a notification that still says *"cancel by today"* is nagging about a dead deadline. On the day the money actually moves, the correct message states that fact.

⚠ **The conversion announcement is never cancelled by a reschedule** *(Wave 10, defect C)*. The escalation is a request and can be waived ("Keeping it"); the announcement is a fact and cannot. On the device, a reschedule after 09:00 on conversion day removed the pending announcement and then dropped its replacement as passed-hour — permanently cancelling the single most important notification in the product. The §6.2 reconciliation is now **structurally unable** to remove a pending announcement dated its own conversion day, whatever the desired plan says; if the plan would drop it, that is a bug in the plan. Only its own day: a day-late "converted today" is dishonest, and a trial cancelled before converting must still take its future announcement down.

Convenient side effect: with the default 2-day buffer the ladder lands at exactly the 5-rung cap.

**Corollary — "Keeping it" cancels the escalation but never the announcement.** §5.2a's *"whether or not the user ever acknowledged anything"* decides this. The escalation is a request to act and can be waived; the announcement is a statement that money started moving, and the user having said "keeping it" a week ago does not make the charge less real.

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

Registered via `UNNotificationCategory`. Tap opens the subscription detail.

**There are two categories, not one** *(corrected in v1.5 — v1.4 described "three buttons" and the verification flow needs its own pair)*:

| Category | Actions |
|---|---|
| Reminder | **Keeping it** · **I'm cancelling** · **Remind me later** |
| Verification | **Yes, it stopped** · **No, I was charged** |

The verification pair is answerable from the notification itself and from Detail, and remains answerable from `.needsManualReview` — the persistent card exists precisely to be answered. A `.stillCharging` record also offers **"Resolved — charges stopped"**, because disputes end.

The reminder category's three buttons:

**⚠ v1.3 contradicted itself here and v1.4 resolves it.** It required both that *"I'm cancelling"* open the stored cancellation URL **and** that all three actions work from the background without launching the UI. **iOS cannot open a URL from a background action handler**, so the two requirements were incompatible.

> **The state work is background-safe and redelivery-idempotent for all three actions. The URL opens only because *"I'm cancelling"* is registered as a foreground action.** The other two stay background.

This is the right split regardless: marking a subscription cancelled must succeed whether or not the app comes to the foreground, while opening a vendor page is inherently a foreground act.


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

#### Today classification — pinned in v1.3

§7.1's descriptions were loose enough that Wave 3 had to legislate. Its three rulings are **adopted**, with one addition:

| Case | Rule |
|---|---|
| Trial action window | `[cancelByDate − reminderLeadDays, conversionDate]` — *Needs action* throughout |
| Pending verification | *Needs action* once its check date arrives; *upcoming* before that |
| **Converted trial, unacknowledged** | *Needs action*, indefinitely, until confirmed — §5.2a. Added in v1.3 |
| `.cancelled` with no `CancellationRecord` | Surfaces as due today rather than silently unwatched — **and is an invariant violation** (§5.2b), so it renders as *needs review*, not as an ordinary due item. Wave 3 was right that the spec didn't acknowledge this state; the answer is that it shouldn't exist, and when it does the user must see it rather than the app quietly deciding for them |

**Pause lives in Detail, not its own screen** *(adopted v1.7)*. §7.1's screen list never gave pause a home despite §5.1 making it first-class — and Wave 7 found the consequence: **nothing in the app could enter `.paused` at all**, so the entire specified pause path was unreachable code. Detail now pauses (with an optional resume date) and resumes; pausing a converted-unflipped trial writes the conversion through first, per the derive-before-you-mutate rule.

### 7.2 Insights

- **Monthly burn** (all cycles normalised) and **annualised total**
- **By category** — the view that answers "how much am I actually spending on AI tools"
- **Next 12 months**, month by month — annual renewals cluster and this is where you see it
- **Price-increase log** across all subscriptions
- **Zombie flags** — see below

**How a trial counts toward burn** *(pinned in v1.3 — §7.2 had a formula for paused spend but never answered this)*. Neither of the tempting answers is right: counting a trial at its converts-to price overstates what the user is paying **now**, and counting it at zero hides money that is about to start moving.

| State | Contribution |
|---|---|
| Unconverted trial | **$0 to current burn**, listed separately under **"Converting soon"** with the amount and date |
| Converted trial (§5.2a) | **Full monthly-equivalent** at `convertsToAmountCents` — it is effectively active, so it counts like anything else |

The "Converting soon" line should state the consequence directly — *"Your monthly burn goes from \$84 to \$95 on 13 Aug"* — because that sentence is the entire product in one line, and it is available before the money moves rather than after.

**⚠ Known gap: burn silently assumes a single currency.** Safe while §2 holds CAD-only, and **wrong the day the first USD subscription is entered** — it will be summed as though it were CAD. Multi-currency is deferred, but this must be a hard failure or a visible warning rather than a silent one when the currency field first varies. *(Flagged by Wave 7; recorded rather than fixed, because the fix is FX-at-charge-date and that is a real feature.)*

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
| **3** ✅ | Store layer (`Packages/OttoUI`, `@MainActor @Observable`, protocol-dependent) then Today / Subscriptions / Add-Edit / Detail. Native components only | ✅ **Done** — commits `9982746`–`909777e`; **156 tests**; layering verified by a failing `import OttoPersistence`. ⚠ Hands-on add-a-subscription pass still unsigned-off by the owner |
| **4** ✅ | Notification engine as a layer-4 `OttoServices` target behind a `NotificationClient` protocol, so the whole engine tests host-side | ✅ **Done** — commits `768525c`–`29811ca`; **203 tests**. Both ⛔ gates pass, incl. the derivation-path test (conversion announcement fires with stored status still `.trial`). ⚠ `BGAppRefreshTask` **not yet observed to run** — by this spec's own standard it does not exist until it is |
| **5** ✅ | Trial, cancellation and verification flows, behind one `SubscriptionFlowService` actor so both entry points share a single state-change path | ✅ **Code done** — commits `30e2e99`–`cb3486f`; **252 tests**. ⛔ **Gate NOT met** — the compressed-timeline trial test on a real device is still outstanding |
| **5.5** ✅ | Hardening: `scripts/verify.sh` (clean-clone build/test/lint), CI covering every package + simulator job, the two pre-CloudKit field additions, ordering guards, the phone-in-a-drawer harness, `docs/manual-verification.md` | ✅ **Done** — HEAD `5a2799e` **verified from a clean clone**: 270 host + 5 simulator = **275 tests**. ⚠ One `OttoPersistence` segfault on the first run, then 9 clean — deliberately left unmasked |
| **7** ✅ | Insights, payment methods, zombie detection, plus the pause UI and the paused-cancellation defer-and-ask path | ✅ **Done** — HEAD `99c3050`, **347 tests**, all Insights figures tested against hand-computed fixtures written *before* implementation. Wave 5.5's segfault did not recur |
| **8** ✅ | Export/import (JSON + CSV), settings, accessibility pass | ✅ **Done** — HEAD `f38eec6`, **403 tests**. Round-trip bit-exact incl. tombstones and fractional-second instants; corruption tested at seven offsets. A SwiftLint custom rule now makes any mention of `storedStatus` an **error** above layer 2 — which caught a live display bug ("Resumes Sep 1" shown forever after Sep 1) |
| **8.5** ✅ | **Model lock**: `CancellationEpisode` + `PauseEpisode`, schema V2 with a custom migration, un-cancel, invalidation fix, export format v2, and the schema-freeze sweep | ✅ **Done** — HEAD `3a69893`, **414 tests**, `verify.sh` green twice from clean clones. `docs/schema-freeze-review.md` written |
| **6A** ✅ | Watermark relocated to a **separate local-only `ModelContainer`** (`OttoDeviceState.store`), plus the §5.4 folding and `evidenceNotes` child table. CloudKit untouched | ✅ **Done** — HEAD `bc5b86d`, **420 tests**, verified twice from clean clones. Schema V3. Migration **refuses rather than degrades** if watermarks can't be carried |
| **6B-Prep** ✅ | §4a's principles, ledger reconciliation, domain watermark removed, the four prerequisites, guard rebuilt to walk the schema the app actually opens | ✅ **Done** — HEAD `8e2ce53`, **449 tests**, verified twice from clean clones. Wholesale collection replace is now **inexpressible**, not merely unused |
| **6B-Prep-2** ✅ | Convergence unified, closure clamped, watermarks reconstructed on import, the describing constructor, `restore()` gated on the kill switch | ✅ **Done** — HEAD `d151122`, **460 tests**. The nil-watermark state is now **inexpressible** from the import flow; `readingRepaired` is a **build error** in UI, repositories and the app target |
| **⭐ DEVICE TESTING** | Install on the owner's iPhone; the four manual gates | ✅ **Unblocked — no code dependency remains** |
| **9A** ✅ | Hands-on fixes: Today permission surface, edit-form mode, export format v4 (ISO 8601 UTC) | ✅ **Done** — HEAD `ab52879`, **475 tests**; all three verified on the physical device |
| **6B-Prep-3** ✅ | Restore dirty flag, evidence-note reparenting, derived package list, `wire_coder_outside_export` lint rule | ✅ **Done** — HEAD `5790167`, **481 tests**. Crash window **interrupted for real** in test; package-list derivation verified by **actually adding a throwaway package** and observing pickup |
| **6B-Prep-4** ⬅ **NEXT, and should be the last** | Min-of-current-and-reconstructed heal; `docs/next-wave.md` + `verify.sh` banner; remove the unasserted `watermarkReconstructions` counter | ⛔ Last code before 6B |

**⭐ `docs/next-wave.md` — the skipped-wave fix** *(adopted v2.5)*. 6B-Prep-3 was recorded correctly in this table and skipped anyway across several sessions. The fix, proposed by Wave 6B-Prep-3 itself:

> A one-line `docs/next-wave.md` naming the next wave and where it is specified. **`verify.sh` prints it at the end of every run and fails if it is missing or empty.** Each wave's closing session updates the line as part of landing.

The reasoning is the general lesson restated: the wave table already recorded the truth; what was missing was **a surface inside the loop you never skip.** Same structural move as gating `restore()` on the kill switch.

**What deliberately is not built:** any attempt to have `verify.sh` validate that a wave was actually *done*. It cannot know, and **a checklist that lies is worse than none.** This wave was lost *between* sessions, not within one — a per-run banner is exactly the right grain.
| **6B** | CloudKit enablement + two-device sync verification | ⛔ Data survives delete-and-reinstall · ⛔ all four manual gates · ⛔ 6B-Prep green · ⛔ the four prerequisites below |

**⛔ Hard prerequisites for enabling CloudKit** *(added v2.0; the audit answered "what is the rollback story" with **"there is no rollback story — there is a backup story," which is not the same thing**)*. `restore()` hard-deletes and re-inserts, which under mirroring is a **mass cloud deletion plus a resurrection vector for offline devices**; sync cannot be switched off without shipping a build; and nothing can purge the zone. All four must exist first:

1. **An automatic pre-enable export snapshot** — taken before the first sync, unprompted. **Boundary:** it is a *floor, not a mirror* — nothing created after it is covered, it lives on the same device as the data it protects, and the user can delete it from Files.
2. **A runtime kill switch** for sync, so disabling it never requires an App Store release. **Boundary:** takes effect at next launch, **not mid-flight**; does nothing on other devices; removes no data anywhere. It stops the bleeding, nothing more.
3. **A zone-purge action.** **Boundary:** a cloud purge **deletes nothing on any device**, and an offline device re-enabling later can **re-create the zone from its own data**. Its cloud half is a seam whose real implementation cannot exist until 6B — **⛔ 6B must test it against a real CloudKit container before any real data exists.**
4a. **⛔ Test the kill-switch refusal against the real mirrored mode on day one of 6B.** `mainSyncMode != .off` is currently a comparison that **cannot be true**, so the guard is unfireable and untestable until the enum grows a second case. Wave 6B-Prep-2 shipped it knowingly and named the flaw in its own defence: *"it becomes checkable the moment the enum grows — but 'supposed to' is doing work in that sentence."* Correct. **"It will be tested once the other case exists" is a promise about a future wave's diligence**, and this project has watched that promise fail at the watermark relocation, the version-pinned guard, and the enum freeze. Day one, not eventually.

4. **A sync-aware `restore()`** that does not express a restore as a mass deletion — upsert by id plus an explicit tombstone diff. **Boundary:** it freezes nothing, so an offline device's post-snapshot edits still land on restored rows by last-writer-wins when it returns.

**⭐ `restore()` must structurally require the kill switch** *(added v2.1)*. Wave 6B-Prep noted that "engage the kill switch before restoring during an incident" is **a documented rule, not a structure** — and observed, correctly, that *this project's history is documentation failing where structure holds*. **`restore()` refuses unless sync is disengaged.** A rule that must be remembered during an incident is a rule that will not be.
| **9** | Real-data dogfood; then TestFlight to the second user | The owner runs it as his only tracker for two weeks |

**Waves 7 and 8 now precede Wave 6** *(reordered in v1.6)*. Three reasons, in ascending order of importance:

1. **Neither depends on CloudKit.** Insights and export/import are pure local features; the original ordering had no technical basis.
2. **Both will surface further §5 model changes** — Insights exercises the paused-burn and zombie fields for the first time, and export/import exercises every field at once. **Model changes are field additions before Wave 6 and schema migrations after.** Every defect these two waves surface is one found on the cheap side of the cliff.
3. **Export/import *is* the CloudKit escape hatch** (§3.5). Building it *after* the one-way door means the migration path is untested at the exact moment data starts flowing through a store the developer cannot read. Building it first means the escape hatch exists before it can be needed.

Wave 6 additionally remains blocked on §10 Decision 2, which reordering gives time to answer properly rather than under deadline.

**Wave 1 before anything else, deliberately.** The date engine is the part that is silently wrong rather than loudly broken, and it is far easier to trust when it exists as pure functions with no UI attached.

---

## 9. Environment

- **Deployment target: iOS 26.0.** <cite index="19-1">iOS 26 is the current public release, at 26.5 as of mid-2026</cite>, and both devices in scope run current software — so there's no reason to carry compatibility shims for older versions.
- ⚠ <cite index="18-1">iOS 27 is in developer beta since June 8, 2026, with public release expected September 2026</cite> — which lands right in the middle of this build. **Develop against the iOS 26 SDK; test on an iOS 27 beta device before shipping to the second user.** Notification behaviour and Focus-mode handling are exactly the sort of thing that shifts in a major release.
- Swift 6 language mode, strict concurrency on from Wave 0. Retrofitting it later is significantly worse.
- Xcode's current release; **SwiftLint only** in CI. *(v1.0 named swift-format alongside it; the two overlap and the second earns nothing. Dropped so the spec and the repo agree.)*

---

## 9b. Findings from the first hands-on session *(Aug 7, 2026)*

Otto was installed on the owner's iPhone and used for about two hours. Three real subscriptions entered: **Subscription A** ($A/mo), **Subscription B** ($B/yr), **Subscription C** ($C/yr) — $N/year now tracked. Export produced and read by a human for the first time.

**Three defects, none caught by 460 tests:**

| # | Defect | Evidence |
|---|---|---|
| **1** | **Today shows no notification banner when permission has never been asked.** A first-launch user sees only "No subscriptions yet"; iOS Settings had no Notifications row at all, proving the request had never fired. The request path *does* exist (Settings → "Turn on reminders…") and the granted state updates live — so this is a **missing surface, not missing logic**. ⚠ **§6 constraint 3 requires exactly this**: an app whose entire value is notifications must not fail silently when it cannot send them | Observed once, cleanly |
| **2** | **The edit form always reopens in "When it started" mode**, displaying the stored anchor under that label regardless of how it was entered. For a Mode B subscription it asserts a start date that never happened — and shows `Started on` and `Next charge` as the **same date** on an annual cycle, which is impossible for a real start date. Root cause is §5.1's back-derivation: the entry mode is **discarded** after save, so the form has nothing to restore | Reproduced 3× |
| **3** | **Export timestamps use Apple's 2001 reference epoch** (`"createdAt": 807839382.279346`) while `expectedDate` and `cycleStartDay` are proper ISO strings. Two conventions in one file — and **this breaks the file's whole purpose**: export/import is the CloudKit escape hatch (§3.5), the reason Waves 7–8 preceded 6, and the argument that settled §10 Decision 2. **A migration format encoded in a platform-specific epoch is not a migration format** — a Kotlin or TypeScript importer produces dates 31 years off unless it knows the offset | Verified in the exported file |

### ✅ All three fixed in Wave 9A — and the diagnosis found something worse

**⭐ The empty-database gate was hiding more than the banner.** The early-return that skipped the notification surface **also skipped the "N subscriptions couldn't be read" card and the read-repair cards** — so an entirely unreadable database would have displayed **"No subscriptions yet"** while suppressing the one card explaining why. That is not a missing banner; **it is a database silently reporting itself as empty**, which is §4a principle 2 (*reads degrade and repair, never fail silently*) defeated by a UI gate rather than by the persistence layer. Found only because the fix required understanding *why* rather than patching the symptom.

**Option (b) was chosen for the edit form**, on a dependency check confirming nothing reads the anchor as a start date — §7.3's zombie report and the usage check-in already accept Mode B anchors. One subtlety mattered in implementing it: **an untouched edit re-describes the stored anchor verbatim rather than re-deriving it**, so saving without touching the date cannot silently shift a clamped month-end phase or re-ask the last-day question the anchor already answers.

**Export v4 trades bit-exactness for portability, deliberately.** The old numeric encoding round-tripped `Date` doubles exactly; ISO milliseconds cannot. The cost is pinned in a named test (`subMillisecondTruncation`) and the round-trip fixtures were changed from decimal to binary-exact fractions, since the old ones pinned precisely the property v4 gives up.

**Original fixes as specified:** (1) surface the not-yet-asked state on Today; (2) either store the entry mode, or **drop the segmented control on edit entirely** and show one unambiguous "Next charge on" field — once a subscription exists, "when did it start" is no longer a question worth asking; (3) ISO 8601 UTC strings, `formatVersion` → 4 per §3.5's policy.

### ⚠ Two candidate findings were withdrawn, and the pattern matters more than the findings

- *"Next charge defaults to today, so a charge landing today is silently skipped."* **False.** The engine returns the first occurrence **on or after** today; entering today's date produces a next charge of today and materializes its ledger row. Correct behaviour, and it also explains why future anchors resolve to themselves with no special-casing.
- *"The payment-method display is too generic."* **Not a defect** — the user typed "Credit card" as the label.

**The pattern:** every confident assertion made *about* the app during the session — that the Claude anchor was nine days wrong, that a future anchor would compute a year late, that today's date would be skipped — **was wrong.** Every correction came from a screenshot. Three of three. **Reasoning about a running app is not evidence about it**, which is the same lesson as Wave 4's non-compiling HEAD, one level up: not just *a green report isn't the artifact*, but *a confident inference isn't an observation either.*

---

## 9a. Known issues

| Issue | Status |
|---|---|
| **`OttoPersistence` segfault (signal 11)** on the first-ever clean-clone verify run — ✅ **probable cause identified in Wave 8.5** | **Resolved, most likely.** SwiftData keeps a **process-global, name-keyed model registry**, and schema V1/V2 deliberately share entity names — so parallel test suites racing across the two schemas die inside `ModelCoders`. Fixed by nesting every persistence suite under one `@Suite(.serialized)` root (sub-second suites, so the lost parallelism is noise). This also retro-explains the Wave 5.5 sighting, which predated V2 but had the same registry contention. **The app is unaffected — it only ever builds one container — but this is worth carrying to Kept if it ever holds two live schema versions.** Originally left unmasked rather than retried, which is why the cause was findable at all |
| **§5.4 paused-cancellation is specified but not implemented** — the defer-and-ask path needs UI, which Wave 5.5 forbade | **The one place code and spec knowingly disagree.** Must be reconciled; now assigned to Wave 7, which has the UI budget |
| **SwiftData's `rollback()` crashes** on a context with pending deletes | Discovered in Wave 8. Import atomicity is therefore structured with **no failure path between the first mutation and the single `save()`** — atomicity by construction rather than by rollback. Worth carrying to any other SwiftData work, Kept included |
| **Test counting has no single command** — 5 Dynamic Type tests are `#if canImport(UIKit)` and compile to nothing under `swift test` on a Mac | Resolved by `verify.sh`, which prints what it can see and **explicitly names what it cannot.** The historical "252" was arithmetically honest; the counting method had simply never been written down |
| **⛔ The `BGAppRefreshTask` expiration path does not stop the work it expires** | **Open, found Aug 2026** by the Gate 2 run — and only findable *because* the isolation crash was fixed first, since expiration was unreachable while the handler trapped on entry. `expirationHandler` calls `work.cancel()`, but `NotificationScheduler.reschedule` has **no cancellation checkpoints**: it never checks `Task.isCancelled` and its awaits do not propagate cancellation. Observed on device: `path=expiration success=false` logged at 22:02:05.985, then the pass ran to completion and logged `path=normal success=true` at 22:02:06.028. **`setTaskCompleted` is therefore called twice, and the app keeps doing work after the OS has reclaimed the task** — on a real background launch that is precisely what expiration exists to prevent, and iOS may suspend or kill the process mid-write. Two things to fix, not one: make completion idempotent (call `setTaskCompleted` exactly once), and give the pass real cancellation checkpoints so cancelling means something |

---

## 10. Open decisions

| # | Decision | Status |
|---|---|---|
| 1 | App name + bundle ID | ✅ **Decided Aug 6 — Otto / `com.arthurzhang.otto`.** Permanent. |
| 2 | Android or paid public distribution within 12 months? | ✅ **Decided Aug 7: no — proceed with CloudKit.** See below. Revocable until Wave 6 begins |
| 3 | Notification time-of-day default | Default set: **09:00 local**, user-editable |
| 4 | Default reminder lead days | Default set: **3 days renewals · 5 days trials**, per-subscription override |
| 5 | Default trial buffer | Default set: **2 days**, per-trial override |

**On the name.** The bundle ID is permanent; the App Store display name is not, and can be changed at any time. So the durable half of this decision is the identifier, and it was chosen to be a proper noun carrying no feature description — a bundle ID like `com.arthurzhang.subtracker` would strand the app the moment it did anything beyond subscriptions. **Otto** additionally echoes *auto*-renewal without stating it, and follows the one naming strategy that has actually worked in this category (§7.4).

| 6 | Add a remote and verify CI | ✅ **Decided Aug 2026.** Remote is `8C9D/otto` (private). **Runner label: `macos-26` is correct and unchanged** — it was never the risk. CI coverage is a strict superset of `verify.sh` (same six checks, plus the simulator job `verify.sh` cannot run, plus `verify.sh` itself). CI is proven able to fail: a deliberate stale-call-site break went red on exactly the Wave 4 error while `App build` stayed green, which is that wave's blind spot reproduced on purpose. `main` is green on all 7 jobs (run `31287691266`). **What the first run actually found were two host-environment test defects — a locale-pinned currency string and an accessibility tree with no client — neither visible to `verify.sh`, which clones the code into the same locale on the same hardware.** See `DECISIONS.md`, "Gate 1". |

**On Decision 2, and what changed.** The v1.0 framing treated this as a coin-flip on the owner's future intentions. Two things since have made it lopsided:

1. **Nothing is validated yet.** The hands-on entry pass is still unsigned, and no real subscription has been tracked end-to-end. Building auth, hosting, and a sync protocol for two known users, before the product has been used once, is speculative work on a speculative premise.
2. **⭐ Wave 8 now precedes Wave 6, which materially changes the calculus.** The central argument for building a backend early was that CloudKit's one-way door makes a future migration expensive. **A tested export/import path, existing and verified before any data enters CloudKit, is most of that cost removed** — the migration becomes "users export and upload" rather than "there is no path."

**The flip condition is unchanged and still live:** a concrete Android or paid-distribution intent inside ~12 months makes CloudKit throwaway work. **Absent that intent, CloudKit is right.** Revocable until Wave 6 begins; after that it is a data migration.

**Decision 2 is the only one with a real deadline.** It is free to defer until Wave 6, and expensive after — once the second user has months of data in her private CloudKit database, moving her off it requires her cooperation rather than a migration script.

---

## Update log

- **2026-08-08 (v2.6 — Wave 10, Notification Delivery & Check-Date Fixes, complete)** — **525 tests** (246 domain + 167 UI + 112 persistence), verified twice from clean clones; five commits ending at *"Record Wave 10 and the decisions behind it"*. The compressed-timeline device run (Aug 8–10 device days) **passed the ⛔ Wave 5 gate** — the conversion announcement fired on a locked screen with the app never opened — and surfaced four real code defects, **all four in the gap between the pure planner and actual delivery**: every engine test ran against a fake whose `add` never throws, and `LiveNotificationClient` had zero coverage. The gap, not the four symptoms, was the wave's subject.
  - **⛔ G — the check-date selector picked an already-landed charge.** Cancelling on the conversion day watched the conversion charge itself, corrupting the dispute summary — the one output with an external audience. `nextChargeDateIfNotCancelled` is now the first occurrence **strictly after** the cancellation day (§5.4), pinned by a reachable-state property test: no dispute summary's charge date can equal or precede its cancellation day. Generalized: **`>= today` is an unsafe default anywhere a past occurrence can be a legitimate already-settled event** — *derive before you mutate* protects the read, not the pick.
  - **⛔ B — the remove-all-then-re-add loss window is inexpressible, not narrowed.** The reschedule is now a diff reconciliation (§6.2): a suspension mid-pass leaves a superset or the correct set, never the empty device the unified log showed at 5 ms distance. Falsified by restoring the old cycle and watching the suspension test's device state come back `[]`.
  - **⛔ C — the conversion announcement is never cancelled by a reschedule** (§6.3): reconciliation is structurally unable to remove a pending announcement dated its own day, so the 09:01-on-conversion-day pass that used to permanently cancel it now leaves it standing. Only its own day — a cancelled-before-conversion trial still takes its future announcement down.
  - **⛔ A — §6.2's "schedule it immediately" had never worked, for anything, since v1.1.** Zero interval triggers existed; the scheduler's drop comment claimed §6.2 would recover what §6.2 never touched. Implemented with 5-second `UNTimeIntervalNotificationTrigger`s, bounded three ways: only while the protected deadline is ahead (planner-structural), never twice (`getDeliveredNotifications`, not a stored flag), and **at the rung's original day** — the first implementation attempt re-dated rungs to "today," minting a fresh identifier every pass and re-warning daily, which an existing §6.4 test caught immediately. The stable identifier IS what makes the delivered-check meaningful.
  - **⛔ D — the gate fixture modeled the easy case** (cancel-by 12 days out, 08:00), which is why A shipped through a green gate. The hard fixtures now exist: entered ON the cancel-by day at 10:03 (the full remaining ladder lands in one run), and first-run-at-09:01-on-conversion-day. Both new subsystems got phone-in-a-drawer tests rather than assumed inheritance.
  - **⛔ H — import summaries counted tombstones as recovered data** ("4 added" with three subscriptions in the app). Counts are now live-record visibility transitions (added/updated/removed/skipped); tombstone movements count nowhere, and the same fix reached the import *preview*, which had the identical defect. The one-mechanism-two-authorities audit swept every counting/listing site; Insights, Today, the zombie report, payment-method overviews, and the CSV were already live-only.
  - **The coverage gap itself:** a `UserNotificationCentering` seam over `UNUserNotificationCenter`, with a fake recording real `UNNotificationRequest` objects — trigger types, per-field date components (timezone deliberately nil), interruption levels, category/action identifiers, and a **throwing `add`** are all now observed host-side rather than assumed.
  - **Also:** unresolved `^[…](inflect: true)` markup rendered literally (nothing in the suite read a *rendered* string — fixed through a helper the tests render, with the learned limit that the English engine pluralizes nouns but does not conjugate verbs); the filtered empty list now states itself per §7.1; `docs/manual-verification.md` carries the corrected clock rule (**never let the clock land past a fire time — tick through it**) and the iOS resurrection mechanism (jumping past a ladder's last rung is unrecoverable by clock manipulation alone).

- **2026-08-08 (v2.5 — Wave 6B-Prep-3 complete)** — **481 tests**, HEAD `5790167`. All four items landed, and two were verified by **actually doing the thing rather than asserting it**: the crash window was **interrupted for real** (production path driven through the first save, stopped before the reconstruction save, a fresh store built over the same files — which answered the restored ledger's edge, not the pre-import date), and the package-list derivation was proven by **committing a throwaway fourth package, observing `verify.sh` pick it up, then dropping it**. The lint rule got the same treatment: probe violations injected, confirmed firing, removed.
  - **⭐ The report flagged its own judgment call rather than burying it.** The dirty flag needed a durable device-local home, which meant adding a model to the *device-state* store while my constraint said "the schema is frozen, stop on model changes." It proceeded and said so. **The judgment was right** — the freeze exists because of CloudKit migration cost, and the device-state store never syncs — and §3.5 now says *which* schema is frozen, since v2.4's wording forced an interpretation.
  - **⚠ "Both branches land safe" overclaimed, and the heal now takes the minimum.** A residual double fault — flag written, main save fails, flag retraction *also* fails — leaves the next access reconstructing over an unreplaced ledger, which can **advance a deliberately rewound watermark past its stranded gap.** Vanishingly narrow, and **the one path where the heal itself points the wrong direction.** Taking the min deviates from v2.1's literal definition; that is correct, because **where a definition and the principle behind it disagree, the principle wins** — watermarks err earlier, never later.
  - **"On launch" was implemented as "before any watermark access"**, guarded at the accessors so there is *no code path* to a stale-ahead watermark regardless of who reads first. Strictly stronger; **recorded in §5.3 precisely because it looks like a deviation and would otherwise get "fixed" back.**
  - **The lint rule's limit is now in the spec, not just the report.** A regex cannot catch an aliased coder, a third-party serializer, or reflective construction — same power class as the two precedent rules. **A rule mistaken for a guarantee is worse than no rule.**
  - **⭐ `docs/next-wave.md` adopted** as the skipped-wave fix, with its own explicit non-goal: `verify.sh` must never claim to validate that a wave was *done*, because it cannot know and **a checklist that lies is worse than none.** The insight underneath is sharp — the wave table recorded the truth all along; what was missing was **a surface inside the loop you never skip.**

- **2026-08-07 (v2.4 — Wave 9A complete, verified on device)** — **475 tests**, HEAD `ab52879`; all three §9b defects fixed and **confirmed on the physical iPhone**, with the three real subscriptions surviving the reinstall intact.
  - **⭐ The empty-database gate was worse than the reported bug.** It hid not just the notification banner but the **"N subscriptions couldn't be read" and read-repair cards** — an entirely unreadable database would have shown "No subscriptions yet" while suppressing the explanation. **A UI gate defeating §4a principle 2**, found only because the fix required diagnosing *why* rather than patching the symptom. Recorded because the general form is worth carrying: **an early return that skips a list can skip everything that renders alongside it.**
  - **New §3.5 rule: only the `Exported*` types may cross a wire.** The sweep found the domain models' own `Codable` conformance encoding `Date` with the encoder's ambient strategy — a default `JSONEncoder` on any future wire reinstates the 2001 epoch. Test-only today; **a representation that is device-local by convention will eventually leave the device.**
  - **⚠ Wave 6B-Prep-3 was specified in v2.2 and never ran.** The device-install session and Wave 9A both jumped over it. Three items outstanding — the **restore dirty flag** (crash window currently leaving *stale-ahead* watermarks, the one direction the design refuses), **evidence-note reparenting** (one id naming two live records, a **collision** in CloudKit specifically), and `verify.sh`'s hand-maintained package list — now joined by the `Codable`-`Date` hazard. **Two of the four are CloudKit blockers**, and it is now the next wave.

- **2026-08-07 (v2.3 — first hands-on session)** — ⭐ **Otto is installed on a physical iPhone and holds three real subscriptions**: Subscription A, Subscription B, Subscription C — **$N/year**. The device build succeeded with **nothing stripped** (all three entitlements verified present before install), and the working tree stayed clean at `d151122`.
  - **⭐⭐ Two of the three subscriptions entered were ones the owner had lost track of.** Subscription B ($B/yr, auto-renew on) and Subscription C ($C/yr) appear **nowhere** in `Personal-Finance-Hub-v2` — the most carefully built financial record he has, with 21 reconciled statements — because both landed in the four statements that lack line detail. He could not remember the Proton amount and was unsure which card paid it. **Annual subscriptions are structurally unrememberable, and that is the product thesis confirmed against his own data rather than against a story.** Proton also renews **17% above** the promo price he paid, an increase he would never have seen coming.
  - **Three defects found by hand, recorded in §9b**, none caught by 460 tests: the missing not-yet-asked notification banner; the edit form reopening in the wrong mode and misreporting its own stored state; and export timestamps in Apple's 2001 epoch, which **breaks the migration format that the entire CloudKit decision rests on**.
  - **⚠ Two candidate findings were withdrawn as wrong** — both were assertions made by reasoning about the app rather than looking at it. **Every confident inference about running behaviour during the session was wrong; every correction came from a screenshot.** Logged as a lesson rather than quietly dropped, because it generalizes Wave 4's *a green report is not the artifact* one level further.
  - **Also confirmed working in real use:** the honest horizon statement ("Reminders scheduled through Nov 5"), the expected-charges ledger matching `today + horizon + maxLead` exactly in both UI and export, the watermark correctly **absent** from the export, live date computation before save, and the cancelling copy — *"Otto never cancels anything for you. It opens the page, records what you did, and later checks that the money actually stopped"* — which states §1's boundary and the Failure-B thesis where the user actually needs it.

- **2026-08-07 (v2.2 — revised against the Wave 6B-Prep-2 report)** — **460 tests** from a clean clone. All five fixes landed, several *structurally*: the nil-watermark state is now **inexpressible** from the import flow, and `readingRepaired` is a **build error** in UI sources, repository protocols and the app target — with the rule **probed to confirm it actually fires** before being trusted, which is the lesson from the guard that went green while checking nothing. ✅ **Device testing is unblocked; no code dependency remains.**
  - **⭐ The fifth "can't articulate" flag has a concrete consequence the report couldn't name.** The rival-cancellation merge copies evidence notes to the winner while tombstoned losers keep their own, so **one note id names two records** — deterministic and lossless, but violating §5.0's premise on purpose. **The feature it breaks is 6B:** CloudKit addresses records by name derived from the identifier, so two live records sharing an id is **a collision in the subsystem about to be enabled.** Fixed by **reparenting rather than copying.** Five for five on that instinct, and the first with a non-latent consequence.
  - **⚠ My v2.1 fix moved a hazard instead of removing it.** Watermark reconstruction changed restore's crash window from leaving **nil** watermarks to leaving **pre-import** ones — which can sit *ahead* of the imported ledger, vouching for rows the restored database doesn't have. **The one direction the design refuses, and invisible where nil was merely known-bad.** Resolved better than either offered option: **restore writes a dirty flag first**, so a crash self-heals via the reconstruction path that already exists. **A fix that relocates a hazard rather than removing it deserves re-examination** — this one got it only because the report said so plainly.
  - **Three silent pins found hiding inside correct ones**, in a sweep specifically hunting stale guards: both new `Outcome` enums were **missing from the hand-maintained enum freeze** (added in v1.9 *after* the freeze was written); `SyncState`'s raw UserDefaults keys had only a round-trip test, so **renaming both sides stayed green while resetting every real device's switches**; the legacy evidence-note id was asserted rule-vs-rule. **A hand-maintained list of things to pin is itself the thing that goes stale.**
  - **Flagged, deliberately not fixed:** `verify.sh`'s `PACKAGES` is a hand list, so a fourth package would be **silently untested**. Correctly left alone — *changing the harness in the same wave whose report depends on it* would undermine the report. Fix next wave by deriving it from `ls Packages`.
  - **Knowingly shipped an unfireable guard and said so:** `mainSyncMode != .off` cannot be true until 6B adds the second case. Honest disclosure in the same wave whose sweep hunts guards that don't fire — 6B must test the refusal.

- **2026-08-07 (v2.1 — revised against the Wave 6B-Prep report)** — **449 tests**, verified twice from clean clones. The three sync-safety principles are implemented **structurally**: delete-on-absence is *removed* rather than disabled, so **wholesale collection replace is inexpressible**; reads repair rather than throw, surfacing repairs into one aggregate needs-review card; the compatibility guard now walks `OttoContainerFactory.mainSchema` — **the schema the app actually opens** — so there is no version name left in it to forget. Four findings, all accepted:
  - **⭐ Two convergence rules pointed in opposite directions** — pause repair kept the *earliest* episode, cancellation reconciliation the *newest*. Each defensible alone; the asymmetry undocumented. **Unified on earliest-wins-and-merge**, matching the ledger rule so all three share one shape. Earliest is also the safer direction for a verification product: an earlier cancellation yields an earlier check date, so the error is watching sooner, never too late.
  - **⚠ Closure could produce an episode ending before it starts.** Harmless today because nothing reads closed-episode durations — and certain to surface the first time any feature computes pause spans. Now clamped to zero duration, which honestly records "recorded, never actually in effect." **Implementing the rule literally and flagging it, rather than silently improving it, is what made this visible.**
  - **⚠ The replace-import watermark reset contradicted v2.0's own correction** — v2.0 said a nil watermark has no safe fallback; replace-import nils every one. Resolved by **reconstructing each watermark from the imported ledger** (the latest imported `expectedDate` *is* "materialized through"), falling back to the anchor and **never to today**. The contradiction is removed rather than documented around.
  - **⭐ The "can't articulate it" instinct was right a fourth time.** The edit path constructs through `readingRepaired` — for a real reason, since editing a degraded record must re-describe it without trapping — but **a write path inheriting the read path's deliberate permissiveness means a future change to repair rules silently changes write validation.** Same one-mechanism-two-authorities smell as `anchorDay` and the domain watermark. A dedicated *describing* constructor, scoped to exactly the shapes the edit form can hold. **This is now the most reliable single signal in the review loop.**
  - **⭐ `restore()` now structurally requires the kill switch.** "Engage the kill switch before restoring during an incident" was a documented rule, and the report's own observation was the decisive one: **this project's history is documentation failing where structure holds.** A rule that must be remembered *during an incident* will not be.
  - **Honest boundaries recorded for all four prerequisites** — what each does *not* protect against, asked for deliberately. The snapshot is a floor not a mirror and sits on the same device; the kill switch acts at next launch, not mid-flight, and only locally; a zone purge deletes nothing on any device and an offline device can re-create the zone; a sync-aware restore freezes nothing. **⛔ The zone purge's cloud half cannot exist until 6B and must be tested against a real container before any real data exists.**

- **2026-08-07 (v2.0 — revised against the Wave 6A report and its CloudKit readiness audit)** — Wave 6A done: **420 tests**, watermark relocated to a **separate `ModelContainer`** rather than a second configuration (that design was **probed empirically first** — SwiftData's staged migration refuses any container whose schema isn't exactly a plan version, so it could never sweep device state out of a synced configuration). Migration **asserts the carry-over while the old column still exists** and **refuses to migrate at all** if the destination is missing. **⚠ The readiness audit is the most consequential document produced in this project: enabling CloudKit as planned would have caused silent data loss.** New §4a states the three principles behind the findings:
  - **⚠⚠ Absence is not deletion.** The aggregate save path soft-deletes any stored child absent from the in-memory array, on the contract that absence means deliberate removal. **Under per-record sync that contract is false** — device A saving a stale snapshot **tombstones device B's just-synced episode, silently.** Now covers evidence notes and the trial too. **Ranked above everything else as the pre-6B change.**
  - **⚠⚠ Invariants that throw at read time convert sync artifacts into dead records.** Two devices pausing independently produces two open pause episodes; the at-most-one-open invariant then throws in mapping, making **the subscription unreadable on every device, permanently, with no repair flow.** Generalised: under sync, any invariant reachable from two devices *will* be violated — reading must **degrade and repair**, never fail. Same lesson as v1.9's backup bug, one level up.
  - **⚠ "The dedup makes the duplication invisible" (§5.3) was wrong.** Uniqueness on `(subscriptionID, expectedDate)` only **prevents** at write time and never **reconciles** later, so two devices materializing concurrently — the normal case, since materialization is deliberately per-device — produce **permanently duplicated ledger rows** with independent acknowledgement state. A deterministic post-sync reconciliation pass is now required.
  - **⭐ A guard had gone silently stale.** The Wave 2 CloudKit-compatibility assertion **stayed green while asserting `OttoSchemaV2` after V3 became real** — checking nothing, reporting success. Now asserts V3 and counts models, so adding one without updating the guard breaks the build. **A guard pinned to a version number stops guarding without ever failing.**
  - **⛔ Four hard prerequisites added before CloudKit can be enabled.** Asked pessimistically for a rollback story, the audit answered that **there isn't one — there's a backup story, which is not the same thing**: `restore()` hard-deletes and re-inserts, a mass cloud deletion plus a resurrection vector for offline devices; sync can't be disabled without shipping a build; nothing can purge the zone.
  - **⚠ My own prompt was wrong and the code was right.** It called a lost watermark "safe but wasteful" — in fact a nil watermark materializes **from today**, skipping the unobserved window: the founding hazard, not waste. Corrected in §5.3, and it is why the migration refuses rather than degrades.
  - **Scope judgment affirmed.** The prompt's steps named the watermark only while its own summary said "relocate the watermark **and reconcile spec v1.9**"; Claude Code implemented all three schema resolutions, reasoning that **a frozen spec describing a model the frozen code doesn't have is exactly the failure this project exists to prevent.** Correct call — and it kept the two extra commits cleanly separable so the narrower reading remained available.
  - **The "can't fully articulate" instinct was right a third time:** the domain `Subscription` still *carries* `lastMaterializedThrough` though persistence no longer stores it there — "whatever the store last told me," the same **one-value-two-authorities** shape as the retired `anchorDay`. Removed in 6B-Prep before sync work touches the read path.

- **2026-08-07 (v1.9 — SCHEMA FROZEN, revised against the Wave 8.5 report)** — **414 tests, `verify.sh` green twice from clean clones**, `docs/schema-freeze-review.md` written. The sweep did what it was for: it produced explicit verdicts including several deliberate *not*-fixes with stated reasons, and it caught **a bug it had introduced itself, in self-review**.
  - **⚠ The watermark relocation is promoted from *Wave 6's first step* to a *precondition*, and Wave 6 is split into 6A and 6B.** The sweep named this the thing it would most regret freezing, and the reasoning is exact: everything depends on "first schema act" actually being first, and **if CloudKit turns on with the watermark still on `StoredSubscription`, the advanced-watermark hazard becomes real silent loss** — the precise failure this app exists to prevent. That is also the shape this project keeps hitting: **a plan depending on a future wave's discipline holding.** Now a verified committed state instead of an intention.
  - **⭐ "The one I can't fully articulate" resolved into a real simplification.** `verificationState` and `outcome` both contained `.verifiedStopped` — the whole smell. Once stated (**state = where the watch is now, open only; outcome = how the episode ended, closed only**) the folding is forced: `.verifiedStopped` leaves `verificationState`, because reaching that result doesn't set a state, it **closes the episode**. Nonsensical combinations stop being representable rather than being forbidden by invariant. **"Tell me what feels wrong even if you can't say why" is a different and more valuable question than "what is broken"** — keep it in every prompt.
  - **⚠ An invariant made backups fail.** Deleting a *paused* subscription tombstones its episodes; the "paused must have an open episode" check then refused the row, so `completeSnapshot()` threw — **a full backup failing because a deleted gym membership existed.** Status-coupled invariants now apply to **live records only**; tombstones sit outside them.
  - **`evidenceNote` became a list**, applying §5.3a's freshly-written lesson to the field the sweep flagged: a long cancellation fight produces a call, an email, a chargeback filing, each with its own date. Same one-to-one-for-something-recurring error, caught while still cheap.
  - **✅ The Wave 5.5 segfault has a probable cause.** SwiftData keeps a **process-global name-keyed model registry**, and V1/V2 deliberately share entity names, so parallel suites racing across schemas die in `ModelCoders`. Fixed by serializing the persistence suites. **It was findable only because it was left unmasked rather than retried** — the Wave 5.5 call to refuse a retry wrapper paid off three waves later.
  - **Deliberate not-fixes, recorded with reasons:** payment-method and category history (additive later, existing meanings unchanged — explicitly noted as the one verdict that knowingly discards data); trial stays one-to-one (a re-offered trial is a new subscription lifetime); `SubscriptionStatus.cancelled` kept despite **no flow ever producing it**, on the grounds that removing a case the week the wire format freezes is worse than reserving it; archive leaves a mid-pause episode open, because billing never resumed and an end date would be fiction.

- **2026-08-07 (v1.8 — SCHEMA-FREEZE CANDIDATE, revised against the Wave 8 report)** — Wave 8 shipped: **403 tests**, round-trip bit-exact including tombstones and fractional-second instants, corruption tested at seven offsets. The v1.7 stored-status rule was enforced with a **SwiftLint custom rule making any mention an error** above layer 2 — which immediately **caught a live display bug** (Detail showing "Resumes Sep 1" forever after Sep 1 had passed). A structural rule finding a real defect within one wave of being written is the strongest argument yet for preferring compiler and lint enforcement over review attention.
  - **⭐⭐ Two findings that are the same modelling error, both caught in the last cheap wave.** §5.4 had **no un-cancel** — an accidental "I'm cancelling" tap is irreversible in-app — and **resume erases pause history**. Both are **one-to-one relationships modelling something that recurs**: a subscription can be cancelled, resubscribed and cancelled again; it can be paused every winter. **Relationship cardinality is the one change class that cannot be made cheaply after Wave 6.** Replaced with `CancellationEpisode` and `PauseEpisode` one-to-many histories; **nothing is ever cleared on exit from a state — exiting writes an end date.** Two instances in one report justifies a systematic sweep rather than two fixes, hence Wave 8.5.
  - **⚠ Price edits silently deleted unacknowledged history.** Invalidation tombstoned *every* `.upcoming` row at the old amount, past-dated included, with nothing to recreate them — so a charge date that passed unconfirmed **vanished from the ledger** the moment the user updated the price. Now: **invalidation never touches past-dated rows.** An unacknowledged past row isn't a mistake to clean up, it's a record of what was expected on a date that already happened; where it's genuinely wrong, **the user deletes it**, because Otto surfaces discrepancies and does not decide history was wrong.
  - **Export format version policy stated:** any field change bumps the version, **additive included**, because `Codable` silently drops unknown keys — a newer export restoring into an older app would lose data with no error anywhere. **Silent loss is the thing this app exists to prevent and must not be the thing it does.**
  - **Also pinned:** settings are device-local and excluded from export; a dangling `paymentMethodID` is a **valid state** rendering as "Unknown payment method," not an error, since partial arrival is routine under CloudKit.
  - **Known issue added:** SwiftData's `rollback()` crashes on a context with pending deletes, so import atomicity is structured with no failure path between first mutation and the single `save()` — atomicity by construction rather than by rollback. Carry to Kept.

- **2026-08-07 (v1.7 — revised against the Wave 7 report)** — Wave 7 shipped: **347 tests**, every Insights figure tested against fixtures **hand-computed before implementation**, and the Wave 5.5 segfault did not recur in any run. **§10 Decision 2 resolved: proceed with CloudKit** — see §10 for why Wave 8 preceding Wave 6 is what made that lopsided rather than close.
  - **⭐ The sharpest finding was one that is *correct today*.** `caughtUpCancellationRecords` filters by **stored** status — flagged not as a bug but as "the stored-vs-effective read pattern that produced the Wave 4 bug." **A dangerous pattern that happens to be correct is a defect waiting for an unrelated change to activate it, silently** — this project's characteristic failure mode. Now a structural rule: **stored `status` is unreadable above layer 2; every status read goes through `effectiveStatus(asOf:)`**, enforced by lint or access control rather than reviewer attention. This is the report finding I'd most want reproduced on Kept.
  - **⚠ §7.2's frozen-price rule has been uncomputable since v1.1.** It priced paused spend at the moment the pause began, and **no field ever recorded when that was** — six versions of a formula with nothing to evaluate it against. `pausedOn` added.
  - **⚠ The specified pause path was unreachable code.** §5.1 made `.paused` first-class from v1.1 and §7.1's screen list never gave it a home, so **nothing in the app could enter the state at all.** Pause now lives in Detail. A spec can describe a state completely and still never say who creates it.
  - **`nextChargeDateIfNotCancelled` made conditionally optional.** v1.1's reasoning stands — an *unknown* date must never get a runtime fallback — but the indefinite-pause path produces a date that is **legitimately, knowably absent**, which is different. Constrained by invariant: `nil` iff `.awaitingResumeDate`, a new verification state that generates no notifications and refuses answers, since there is no unverified assertion to confirm.
  - **The watermark's storage is now specified, not just its policy.** v1.6 said device-local; Wave 7 correctly noted it still physically lives on `StoredSubscription` and that SwiftData cannot exclude one property from CloudKit sync. It moves to a **second local-only `ModelConfiguration`** — **Wave 6's first schema act**, and **excluded from Wave 8's export.**
  - **Backwards edits rewind the watermark**, generalized from the pause case: any edit moving a billing sequence earlier rewinds to the earliest affected date.
  - **Known gap recorded:** burn assumes a single currency. Safe while CAD-only, wrong the day a USD subscription is entered. Must fail loudly rather than silently when the currency field first varies.

- **2026-08-07 (v1.6 — revised against the Wave 5.5 report)** — **HEAD is now verified from a clean clone** (`5a2799e`, 270 host + 5 simulator = 275 tests), `verify.sh` exists as the pre-report gate, CI covers every package, and the two pre-CloudKit field additions have landed. The Wave 4 non-compiling-HEAD problem now has a mechanism preventing it rather than a resolution to be careful.
  - **⭐⭐ The founding scenario escaped a *fourth* time — through the pause subsystem.** The watermark advances while a subscription is paused, so a pause ending Sep 1 with the app unopened until Oct 15 leaves two real charges **permanently unbackfillable**. Fixed by applying §5.2a's pattern where it had been missed: **a pause with `pauseEndsOn` resumes by derivation**, and an indefinite pause **freezes the watermark** instead. Generalized into a design rule: ***any state whose exit is a known future date must exit by derivation.*** A state that waits to be told it has ended will eventually not be told. Four escapes through four mechanisms is the strongest evidence yet that this scenario needs structural enforcement rather than per-wave vigilance — which is what Wave 5.5's `PhoneInADrawerTests` harness, with its file-level contract requiring new time-dependent subsystems to add a test, now provides.
  - **The watermark is device-local and unsynced** (decided rather than deferred to Wave 6). Wave 5.5 correctly flagged its merge behaviour as undefined; LWW is dangerous in one direction — a *regressed* watermark merely repeats idempotent work, but an *advanced* one causes a device to skip charge dates never materialized anywhere. CloudKit cannot express "merge by minimum," so the answer is not to sync it. Watermark writes also must not bump `updatedAt`, or every scheduler pass looks like a user edit.
  - **`expectedChargeAmountCents` corrected to optional.** There is no honest non-optional default for a record whose amount was never captured, and **a fabricated zero in a document destined for a bank is worse than an absence.**
  - **⚠ Wave order changed: 7 and 8 now precede 6.** Neither depends on CloudKit; both will surface further §5 changes while those are still field additions rather than migrations; and **export/import *is* the CloudKit escape hatch**, so building it after the one-way door leaves the migration path untested exactly when data starts flowing into a store the developer cannot read.
  - **Known-issues section added (§9a)**, recording the unmasked segfault, the one place code and spec knowingly disagree, and the test-counting resolution. The "252" figure was arithmetically honest all along — 5 simulator-only tests compile to nothing under `swift test`; what was missing was a written counting method.

- **2026-08-07 (v1.5 — revised against the Wave 5 report)** — Wave 5 shipped: **252 tests**, both cancellation entry points routed through one `SubscriptionFlowService` actor so identical state is guaranteed *by construction* rather than by test. Six findings, one of which is about process rather than code:
  - **⚠⚠ Wave 4's committed HEAD did not compile.** A commit changed `NotificationPlanIdentifier.snooze` without updating a domain test that called it, so **"203 tests passing" was not reproducible from the commit.** Not dishonesty — the suite passed before a final refactor — but it means a green report is not evidence about the artifact. **This is the concrete cost of five waves without CI**, and it converts the remote-and-CI item from hygiene into the fix for a demonstrated failure. Repaired by updating the call and *adding* an assertion rather than deleting the test.
  - **⚠ A real check-date bug shipped in Wave 4** and was caught here: `startCancelling` flipped the status **before** computing the check date, and `billingAnchor(asOf:)` keys off stored status — so a converted-but-unflipped trial cancelled after conversion watched **Sep 1 instead of Aug 31**. The differentiating feature, aimed at the wrong day. Generalized into a spec rule: **derive before you mutate**, and prefer deriving from data that survives the mutation. Worth noting that §5.2a's derived-status design was *not* what failed — **ordering inside a single operation is a bug class pure functions cannot prevent**, because the read and the write are each individually correct.
  - **⚠ The founding scenario slipped through a third mechanism.** §5.3 materialized from `today` forward, so a trial converting while the app is closed has its conversion date **behind** `today` on the first pass — the most important charge in the product, with no ledger row, no verification, no price-mismatch coverage, in exactly the phone-in-a-drawer case. Fixed with a **`lastMaterializedThrough` watermark** so no charge date can pass unobserved between runs. **Pattern now explicit: §5.2a fixed this in status derivation, v1.5 in the ledger — every new subsystem must be tested against the phone-in-a-drawer case rather than assumed to inherit it.**
  - **The dispute amount was a heuristic.** The check *date* is stored at cancellation because it is unrecoverable later; the *amount* has the same property and wasn't. `expectedChargeAmountCents` added — **the dispute summary is the artifact that ends at a bank, and nothing in it should be inferred.**
  - **Add/Edit could silently delete a confirmed conversion's `TrialTerm`**, because the form derived its trial toggle from `status == .trial`. That record is what §7.3's zombie report needs. New invariant: a `TrialTerm` on a non-`.trial` subscription is **history, not a toggle**.
  - **Cancelling a paused subscription** now specified: check date is the first occurrence on or after `pauseEndsOn`; with no resume date, **defer and ask** rather than guess — a verification answered against a fabricated date produces false confidence exactly where the product promises certainty.
  - **Folded in:** `PriceChange.Source.trialConversion`; verification as its own notification category with two actions, since v1.4's "three buttons" didn't describe them.

- **2026-08-07 (v1.4 — revised against the Wave 4 report)** — Wave 4 shipped: **203 tests**, engine behind a `NotificationClient` protocol so it tests host-side rather than needing a device. Both gates pass, including the one that matters — the conversion announcement firing with the stored status never flipped, which proves §5.2a's derivation path rather than the persisted one. One adjudication and eight findings:
  - **⭐ `acknowledgedAt` did not exist, so two promised behaviours were unimplementable.** §6.4's *"Keeping it"* and §6.3's *"remainder is cancelled on acknowledgement"* both named a state with no field behind it — and because rescheduling is cancel-all-then-replan, **the silenced reminders get replanned right back in the same cycle.** Wave 4 knowingly under-delivered here rather than inventing a schema. Field added; **must land before Wave 6.**
  - **Adopted: the conversion announcement *is* the trial ladder's final rung.** §6.3 and §5.2a both claimed conversion day. The announcement wins because by then the cancel-by deadline has already passed, so a notification still saying *"cancel by today"* nags about a dead deadline while money is moving. **"Keeping it" cancels the escalation but never the announcement** — the escalation is a request and can be waived; the announcement is a fact.
  - **§6.4 contradicted itself:** it required "I'm cancelling" to open a URL *and* all three actions to work from the background. iOS cannot open a URL from a background handler. Resolved by splitting — state work background-safe for all three, URL opening via a foreground-marked action.
  - **Status changes still orphaned `.upcoming` rows.** v1.3's invalidation covered anchor/cycle/amount edits only, so pausing or archiving left phantom charges in Detail. Generalized to any change altering the expected sequence.
  - **Which tombstones block re-materialization, pinned:** tombstoned `.upcoming` rows are invalidation artifacts and must **not** block, or a corrected sequence can never materialize; tombstoned rows in any other state are deliberate history removal and must.
  - **Snoozes were outside the budget model.** They occupy real slots, so the effective planning limit is `64 − pendingSnoozes`, and they rank above P1 — an explicit user request outranks an inferred schedule.
  - **§5.2b's "loudly" was undefined**, and the actual read policy (skip-with-log) is loud in the console and invisible in the UI — meaning an unmappable subscription **vanishes from the user's view**, the worst available failure for this product. Now an aggregate needs-review card; aggregate because Wave 6 makes partial records routine.
  - **Catch-up with lead ≥ cycle length** now emits exactly one reminder (the earliest un-warned charge), and Add/Edit warns on the configuration, which is nearly always a mistake.
  - **Noted, not a defect:** the three-strike counter has no incrementer until Wave 5, so verification roll-forward is unbounded until then.

- **2026-08-07 (v1.3 — revised against the Wave 3 report)** — Wave 3 shipped: **156 tests**, store layer built before any view, and the layering claim *verified rather than asserted* (adding `import OttoPersistence` to a UI file fails to build). Seven findings; one of them is the most serious defect in the project so far:
  - **⚠⚠ §5.2a — Otto reproduced its own founding failure.** Nothing in the spec said who flips `.trial` → `.active`, or when. Followed literally, a user who **ignores a trial** — the exact founding scenario — leaves the status at `.trial` forever, so no charge after the conversion row is ever materialized or reminded about. **The FoodApp case, rebuilt.** Worse, the obvious fix (Wave 5's flow handles it when the user taps) recreates the failure precisely, because the scenario *is* the user not tapping. **Resolved by making conversion derived, not awaited:** `effectiveStatus(asOf:)` treats a past-conversion trial as active, so a trial that converts with the phone in a drawer for six weeks still materializes and still reminds. Persistence of the flip is an optimisation; **no behaviour may depend on it.** Otto also now announces the conversion — a statement that money started moving, not a request to act.
  - **Three model invariants declared (§5.2b)** after Wave 3 found `.trial`-without-`TrialTerm` silently no-op'ing in **three separate places**. Silent no-ops in separate switch arms are how two code paths eventually disagree; each is now enforced at construction and surfaced loudly.
  - **Schedule changes orphaned ledger rows (§5.3).** Editing an anchor or cycle left `.upcoming` rows from the old sequence in place, showing the user phantom charges on dates that will never arrive. Now: soft-delete non-matching `.upcoming` rows on save and re-materialize; never touch rows in any other state, because a confirmed charge is history.
  - **`cycleStartDay` immutability clarified** in the direction Wave 3 read it — no in-place mutation *by code*, ever; a user correcting a mis-entered date is a correction, not drift.
  - **Trial burn pinned (§7.2):** \$0 to current burn, shown separately as "Converting soon" with the date and the resulting figure. Counting it at the converts-to price overstates today; counting it at zero hides money about to move.
  - **Today classification rules adopted** from Wave 3's rulings, plus the converted-unacknowledged-trial case, plus the ruling that a `.cancelled` subscription with no record is an *invariant violation surfaced as needs-review* rather than an ordinary due item.
  - **`unansweredCheckCount` added** to `CancellationRecord` — §5.4's three-cycle cap had no field to count in. **`PriceChange.recordedAt` dropped** as a duplicate of §5.0's `createdAt`.
  - **§5.1's Mode B claim corrected.** v1.2 said the disambiguation prompt "removes the only systematic inaccuracy"; it doesn't — 29- and 30-anchored subscriptions stay unrecoverable from a Feb 28 entry. Overclaim replaced with the accurate, narrower statement.

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
