import Foundation

/// A tracked subscription (spec §5.1) - a pure value type. Persistence records map to
/// and from this shape; the domain never sees optionals-with-defaults or framework types.
public struct Subscription: Identifiable, Hashable, Codable, Sendable {
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
