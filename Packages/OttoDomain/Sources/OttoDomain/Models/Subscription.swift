import Foundation

/// A tracked subscription (spec §5.1) - a pure value type. Persistence records map to
/// and from this shape; the domain never sees optionals-with-defaults or framework types.
///
/// Construction enforces spec §5.2b's first invariant: a `.trial` subscription must
/// carry a `TrialTerm`, because without one §5.2a has no `conversionDate` to derive
/// anything from. Wave 3 found that state silently no-op'ing in three separate places;
/// it is now unconstructible in process (precondition) and undecodable from data
/// (throwing `Codable`), and the mapping layer refuses it loudly before reaching here.
public struct Subscription: Identifiable, Hashable, Sendable {
    /// Client-generated, so there is never an autoincrement to reconcile against a
    /// server later (spec §3.5).
    public let id: UUID

    public var name: String
    public var vendorURL: URL?
    public var category: Category
    public var status: SubscriptionStatus

    /// The current price in integer cents - money is never floating point (spec §3.5).
    public var amountCents: Int

    /// ISO 4217 code. v1 is CAD-only, but the field exists on every record from day one.
    public var currencyCode: String

    public var cycle: BillingCycle

    /// The anchor date every billing date is computed from (spec §4.2): entered
    /// directly (mode A) or back-derived once from a next-billing-date via
    /// `anchor(fromNextBillingDate:cycle:)` (mode B). Declared `let` deliberately:
    /// overwriting the anchor with a computed date is exactly how month-end drift
    /// gets in, so nothing may ever write it back.
    public let cycleStartDay: CalendarDay

    /// Days before a billing date its reminder fires. Per-subscription; the default
    /// comes from settings at the UI layer, not from the domain.
    public var reminderLeadDays: Int

    /// Whether a second renewal reminder fires on the billing day itself (spec §6.3).
    public var sameDayReminder: Bool

    /// When a paused subscription resumes billing; drives the resume reminder.
    /// Meaningful only while `status` is `.paused` (spec §5.1).
    public var pauseEndsOn: CalendarDay?

    /// The day the pause began; meaningful only while `status` is `.paused`.
    /// Added in Wave 7 because §5.1 pins paused spend to "the monthly-equivalent
    /// at the price frozen when the pause began" - a rule that is uncomputable
    /// without knowing when that was. Nil on records paused before the field
    /// existed; Insights then falls back to the current price, which is the
    /// honest answer when the freeze point is unknown.
    public var pausedOn: CalendarDay?

    /// The materialization watermark (spec §5.3, v1.5): the last day through which
    /// a ledger pass has observed this subscription's expected charges. The window
    /// reaches BACKWARDS from today to this day, so a charge date that fell while
    /// the app was closed - the founding scenario's conversion - still gets its
    /// row, however long the gap. Initialised at entry to the later of the anchor
    /// and the entry day (so Mode B never backfills history it had no rows for);
    /// nil on records created before v1.5, which materialize from today once and
    /// carry a watermark thereafter. Advanced only by a successful ledger pass.
    public var lastMaterializedThrough: CalendarDay?

    /// The trial this subscription started as, when it started as one (spec §5.2).
    public var trial: TrialTerm?

    public var paymentMethodID: UUID?
    public var cancellationURL: URL?

    /// Human instructions for cancelling: "phone only, 1-800-..., mention retention offer".
    public var cancellationNotes: String?

    /// The last day the user recalls using the service; feeds zombie detection (spec §7.3).
    public var lastUsedDate: CalendarDay?

    public var notes: String?

    /// UTC instants for sync conflict resolution (spec §3.5). These are audit
    /// timestamps, not billing dates - which is why they are `Date` while billing
    /// days are `CalendarDay`. Callers inject them; the domain never reads a clock.
    public var createdAt: Date
    public var updatedAt: Date

    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(
        id: UUID,
        name: String,
        vendorURL: URL? = nil,
        category: Category,
        status: SubscriptionStatus,
        amountCents: Int,
        currencyCode: String,
        cycle: BillingCycle,
        cycleStartDay: CalendarDay,
        reminderLeadDays: Int,
        sameDayReminder: Bool = false,
        pauseEndsOn: CalendarDay? = nil,
        pausedOn: CalendarDay? = nil,
        lastMaterializedThrough: CalendarDay? = nil,
        trial: TrialTerm? = nil,
        paymentMethodID: UUID? = nil,
        cancellationURL: URL? = nil,
        cancellationNotes: String? = nil,
        lastUsedDate: CalendarDay? = nil,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        precondition(
            status != .trial || trial != nil,
            "A .trial subscription must have a TrialTerm (spec §5.2b)"
        )
        self.id = id
        self.name = name
        self.vendorURL = vendorURL
        self.category = category
        self.status = status
        self.amountCents = amountCents
        self.currencyCode = currencyCode
        self.cycle = cycle
        self.cycleStartDay = cycleStartDay
        self.reminderLeadDays = reminderLeadDays
        self.sameDayReminder = sameDayReminder
        self.pauseEndsOn = pauseEndsOn
        self.pausedOn = pausedOn
        self.lastMaterializedThrough = lastMaterializedThrough
        self.trial = trial
        self.paymentMethodID = paymentMethodID
        self.cancellationURL = cancellationURL
        self.cancellationNotes = cancellationNotes
        self.lastUsedDate = lastUsedDate
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Derived anchor components

extension Subscription {
    /// Spec §5.1's `anchorDay` (1-31, month and year cycles): derived from
    /// `cycleStartDay` rather than stored beside it, so the two can never disagree.
    public var anchorDay: Int { cycleStartDay.day }

    /// Spec §5.1's `anchorMonth` (1-12, year cycles), derived for the same reason.
    public var anchorMonth: Int { cycleStartDay.month }
}

// MARK: - Effective status (spec §5.2a)

extension Subscription {
    /// The status every consumer acts on. Conversion is DERIVED, never awaited: a
    /// `.trial` whose `conversionDate` has arrived IS `.active`, whether or not any
    /// flow ever wrote the flip through. The founding failure is a user who is not
    /// paying attention, so nothing may depend on the user acting, and nothing may
    /// depend on the status flip having been persisted - a trial that converts while
    /// the phone is in a drawer for six weeks still bills, still materializes, and
    /// still reminds the moment anything asks.
    ///
    /// Pause resume is derived by the same rule (spec §5.2a, v1.6): a `.paused`
    /// subscription past its `pauseEndsOn` IS `.active` - the vendor resumed
    /// billing on schedule whether or not the user opened the app. Any state
    /// whose exit is a known future date must exit by derivation; a state that
    /// waits to be told it has ended will eventually not be told.
    public func effectiveStatus(asOf today: CalendarDay) -> SubscriptionStatus {
        if isConvertedTrial(asOf: today) || isResumedPause(asOf: today) { return .active }
        return status
    }

    /// True when the stored status still says `.paused` but `pauseEndsOn` has
    /// arrived - billing has resumed on the vendor's side (spec §5.2a, v1.6).
    /// An indefinite pause (nil `pauseEndsOn`) has no derivable resume date and
    /// never resumes this way; it freezes the materialization watermark instead
    /// (spec §5.3) and waits for a manual resume, which backfills from it.
    public func isResumedPause(asOf today: CalendarDay) -> Bool {
        status == .paused && pauseEndsOn.map { today >= $0 } ?? false
    }

    /// True when the stored status still says `.trial` but the conversion date has
    /// passed - the converted-but-never-acknowledged state that must stay visible
    /// (spec §7.1) and announce itself (Wave 4).
    public func isConvertedTrial(asOf today: CalendarDay) -> Bool {
        status == .trial && trial.map { today >= $0.conversionDate } ?? false
    }

    /// The anchor the billing sequence runs from as of `today`: on conversion the
    /// paid sequence takes over at `conversionDate` (spec §5.2a). For every other
    /// state - including an `.active` subscription whose conversion was persisted
    /// with a rebased `cycleStartDay` - it is the stored anchor.
    public func billingAnchor(asOf today: CalendarDay) -> CalendarDay {
        guard isConvertedTrial(asOf: today), let trial else { return cycleStartDay }
        return trial.conversionDate
    }

    /// The expected charge amount as of `today`: `convertsToAmountCents` once a
    /// trial has converted (spec §5.2a), the stored amount otherwise.
    public func billingAmountCents(asOf today: CalendarDay) -> Int {
        guard isConvertedTrial(asOf: today), let trial else { return amountCents }
        return trial.convertsToAmountCents
    }

    /// The persisted status flip §5.2a permits once the user confirms they know
    /// the trial converted - "the app may write the status through" - built as a
    /// new value because `cycleStartDay` is immutable in place: status `.active`,
    /// the paid sequence's anchor (the conversion date), the converted amount.
    /// The trial term is RETAINED: confirming records that the user saw the
    /// conversion, it deletes nothing - "this converted and I noticed late" is
    /// exactly the data the zombie report needs (Wave 7).
    ///
    /// Nil unless the subscription is a converted-unacknowledged trial, which
    /// also makes the caller's flow idempotent: once flipped, there is nothing
    /// to confirm.
    public func confirmingConversion(asOf today: CalendarDay, at now: Date) -> Subscription? {
        guard isConvertedTrial(asOf: today), let trial else { return nil }
        return Subscription(
            id: id,
            name: name,
            vendorURL: vendorURL,
            category: category,
            status: .active,
            amountCents: trial.convertsToAmountCents,
            currencyCode: currencyCode,
            cycle: cycle,
            cycleStartDay: trial.conversionDate,
            reminderLeadDays: reminderLeadDays,
            sameDayReminder: sameDayReminder,
            pauseEndsOn: pauseEndsOn,
            pausedOn: pausedOn,
            lastMaterializedThrough: lastMaterializedThrough,
            trial: trial,
            paymentMethodID: paymentMethodID,
            cancellationURL: cancellationURL,
            cancellationNotes: cancellationNotes,
            lastUsedDate: lastUsedDate,
            notes: notes,
            createdAt: createdAt,
            updatedAt: now,
            deletedAt: deletedAt
        )
    }
}

// MARK: - Codable

extension Subscription: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, vendorURL, category, status, amountCents, currencyCode
        case cycle, cycleStartDay, reminderLeadDays, sameDayReminder, pauseEndsOn, pausedOn
        case lastMaterializedThrough
        case trial, paymentMethodID, cancellationURL, cancellationNotes
        case lastUsedDate, notes, createdAt, updatedAt, deletedAt
    }

    // Hand-written so decoding routes through the §5.2b invariant instead of
    // assigning stored properties directly, which is what a synthesized decoder does.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(SubscriptionStatus.self, forKey: .status)
        let trial = try container.decodeIfPresent(TrialTerm.self, forKey: .trial)
        guard status != .trial || trial != nil else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A .trial subscription must have a TrialTerm (spec §5.2b)"
            ))
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            vendorURL: try container.decodeIfPresent(URL.self, forKey: .vendorURL),
            category: try container.decode(Category.self, forKey: .category),
            status: status,
            amountCents: try container.decode(Int.self, forKey: .amountCents),
            currencyCode: try container.decode(String.self, forKey: .currencyCode),
            cycle: try container.decode(BillingCycle.self, forKey: .cycle),
            cycleStartDay: try container.decode(CalendarDay.self, forKey: .cycleStartDay),
            reminderLeadDays: try container.decode(Int.self, forKey: .reminderLeadDays),
            sameDayReminder: try container.decode(Bool.self, forKey: .sameDayReminder),
            pauseEndsOn: try container.decodeIfPresent(CalendarDay.self, forKey: .pauseEndsOn),
            pausedOn: try container.decodeIfPresent(CalendarDay.self, forKey: .pausedOn),
            lastMaterializedThrough: try container.decodeIfPresent(
                CalendarDay.self, forKey: .lastMaterializedThrough
            ),
            trial: trial,
            paymentMethodID: try container.decodeIfPresent(UUID.self, forKey: .paymentMethodID),
            cancellationURL: try container.decodeIfPresent(URL.self, forKey: .cancellationURL),
            cancellationNotes: try container.decodeIfPresent(String.self, forKey: .cancellationNotes),
            lastUsedDate: try container.decodeIfPresent(CalendarDay.self, forKey: .lastUsedDate),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(vendorURL, forKey: .vendorURL)
        try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status)
        try container.encode(amountCents, forKey: .amountCents)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(cycle, forKey: .cycle)
        try container.encode(cycleStartDay, forKey: .cycleStartDay)
        try container.encode(reminderLeadDays, forKey: .reminderLeadDays)
        try container.encode(sameDayReminder, forKey: .sameDayReminder)
        try container.encodeIfPresent(pauseEndsOn, forKey: .pauseEndsOn)
        try container.encodeIfPresent(pausedOn, forKey: .pausedOn)
        try container.encodeIfPresent(lastMaterializedThrough, forKey: .lastMaterializedThrough)
        try container.encodeIfPresent(trial, forKey: .trial)
        try container.encodeIfPresent(paymentMethodID, forKey: .paymentMethodID)
        try container.encodeIfPresent(cancellationURL, forKey: .cancellationURL)
        try container.encodeIfPresent(cancellationNotes, forKey: .cancellationNotes)
        try container.encodeIfPresent(lastUsedDate, forKey: .lastUsedDate)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}
