import Foundation
import Observation
import OttoDomain

/// The Add/Edit screen's model (spec §7.1 item 3) - the screen that decides
/// whether the app gets used.
///
/// Every date the screen shows is computed live by the domain as the user types;
/// the user is never asked to do date arithmetic. Both §5.1 entry modes write the
/// same field: mode A stores the entered start date as the anchor, mode B stores
/// the entered next-charge date (a real occurrence anchors its own sequence), with
/// the last-day-of-month question resolving the one input the date alone cannot.
@MainActor
@Observable
public final class SubscriptionFormModel {

    // MARK: - Entry mode

    /// Spec §5.1's two entry modes, both required and equally prominent.
    public enum EntryMode: String, CaseIterable, Sendable {
        /// Mode A - "I know when it started".
        case startDate
        /// Mode B - "I know my next charge" - what most existing subscriptions
        /// need, because nobody remembers when they signed up for Netflix.
        case nextCharge
    }

    /// The user's answer to the §5.1 last-day question, when it is asked.
    public enum LastDayAnswer: Sendable {
        /// "It's the last day of the month" - anchor month-end, clamping forever.
        case lastDayOfMonth
        /// "It's specifically that day" - anchor the entered day number.
        case enteredDay
    }

    /// The friendly cadence names the UI offers; the domain stores one shape.
    public enum CyclePreset: String, CaseIterable, Sendable {
        case weekly, biweekly, monthly, quarterly, semiannual, annual, everyNDays

        var named: BillingCycle? {
            switch self {
            case .weekly: .weekly
            case .biweekly: .biweekly
            case .monthly: .monthly
            case .quarterly: .quarterly
            case .semiannual: .semiannual
            case .annual: .annual
            case .everyNDays: nil
            }
        }
    }

    // MARK: - Fields

    public var name: String
    public var category: OttoDomain.Category
    /// The price as typed, bound to a locale-aware currency field; cents are
    /// derived, never re-parsed from a string.
    public var amount: Decimal?
    public var cyclePreset: CyclePreset {
        didSet { lastDayAnswer = nil }
    }
    public var customCycleDays: Int {
        didSet { lastDayAnswer = nil }
    }
    public var entryMode: EntryMode {
        didSet { lastDayAnswer = nil }
    }
    public var startDate: CalendarDay
    public var nextChargeDate: CalendarDay {
        didSet { lastDayAnswer = nil }
    }
    /// Set by the disambiguation prompt; cleared whenever the inputs it answered
    /// for change.
    public var lastDayAnswer: LastDayAnswer?

    public var isTrial: Bool {
        didSet {
            // Trials default to a longer lead (spec §10) - but only an untouched
            // default swaps, never a value the user chose.
            if isTrial && reminderLeadDays == Self.defaultRenewalLeadDays {
                reminderLeadDays = Self.defaultTrialLeadDays
            } else if !isTrial && reminderLeadDays == Self.defaultTrialLeadDays {
                reminderLeadDays = Self.defaultRenewalLeadDays
            }
        }
    }
    public var trialStartDate: CalendarDay
    public var trialLengthDays: Int
    public var trialBufferDays: Int

    public var reminderLeadDays: Int
    public var sameDayReminder: Bool
    public var paymentMethodID: UUID?
    public var vendorURLText: String
    public var cancellationURLText: String
    public var cancellationNotes: String
    public var notes: String

    // MARK: - Identity

    /// The subscription being edited, or nil when adding.
    public let original: Subscription?
    private let newID: UUID
    private let trialID: UUID
    private let trialCreatedAt: Date
    private let dates: DateProvider

    /// Spec §10 defaults: 3 lead days for renewals, 5 for trials, 2 buffer days.
    /// The settings screen that makes them editable is Wave 8.
    public static let defaultRenewalLeadDays = 3
    public static let defaultTrialLeadDays = 5
    public static let defaultTrialBufferDays = 2

    /// A blank form for adding.
    public init(dates: DateProvider = .live) {
        let today = dates.today()
        self.original = nil
        self.newID = UUID()
        self.trialID = UUID()
        self.trialCreatedAt = dates.now()
        self.dates = dates
        self.name = ""
        self.category = .other
        self.amount = nil
        self.cyclePreset = .monthly
        self.customCycleDays = 30
        self.entryMode = .nextCharge
        self.startDate = today
        self.nextChargeDate = today
        self.lastDayAnswer = nil
        self.isTrial = false
        self.trialStartDate = today
        self.trialLengthDays = 30
        self.trialBufferDays = Self.defaultTrialBufferDays
        self.reminderLeadDays = Self.defaultRenewalLeadDays
        self.sameDayReminder = false
        self.paymentMethodID = nil
        self.vendorURLText = ""
        self.cancellationURLText = ""
        self.cancellationNotes = ""
        self.notes = ""
    }

    /// A form prefilled from an existing subscription.
    public init(editing subscription: Subscription, dates: DateProvider = .live) {
        self.original = subscription
        self.newID = subscription.id
        self.trialID = subscription.trial?.id ?? UUID()
        self.trialCreatedAt = subscription.trial?.createdAt ?? dates.now()
        self.dates = dates
        self.name = subscription.name
        self.category = subscription.category
        self.amount = Decimal(subscription.amountCents) / 100
        self.customCycleDays = subscription.cycle.unit == .day ? subscription.cycle.interval : 30
        self.cyclePreset = Self.preset(for: subscription.cycle)
        // Editing shows mode A prefilled with the stored anchor: the anchor is the
        // one fact actually on record, and round-tripping it through mode B would
        // re-derive what is already known.
        self.entryMode = .startDate
        self.startDate = subscription.cycleStartDay
        self.nextChargeDate = dates.today()
        self.lastDayAnswer = nil
        self.isTrial = subscription.status == .trial
        self.trialStartDate = subscription.trial?.startDate ?? dates.today()
        self.trialLengthDays = subscription.trial?.lengthDays ?? 30
        self.trialBufferDays = subscription.trial?.bufferDays ?? Self.defaultTrialBufferDays
        self.reminderLeadDays = subscription.reminderLeadDays
        self.sameDayReminder = subscription.sameDayReminder
        self.paymentMethodID = subscription.paymentMethodID
        self.vendorURLText = subscription.vendorURL?.absoluteString ?? ""
        self.cancellationURLText = subscription.cancellationURL?.absoluteString ?? ""
        self.cancellationNotes = subscription.cancellationNotes ?? ""
        self.notes = subscription.notes ?? ""
    }

    private static func preset(for cycle: BillingCycle) -> CyclePreset {
        CyclePreset.allCases.first { $0.named == cycle } ?? .everyNDays
    }

    // MARK: - Derived values, computed live

    public var cycle: BillingCycle? {
        cyclePreset.named ?? BillingCycle(unit: .day, interval: customCycleDays)
    }

    /// The entered price in integer cents (spec §3.5), rounded to the cent.
    public var amountCents: Int? {
        guard let amount, amount >= 0 else { return nil }
        let rounding = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: amount * 100).rounding(accordingToBehavior: rounding).intValue
    }

    /// Mode A's live confirmation: the next billing date the entered start and
    /// cycle produce. Includes a charge landing today.
    public var computedNextBillingDate: CalendarDay? {
        guard entryMode == .startDate, let cycle else { return nil }
        return nextBillingDate(after: dates.today().adding(days: -1), anchor: startDate, cycle: cycle)
    }

    /// The month-end anchor the §5.1 question offers, when the entered next-charge
    /// date is ambiguous - nil means no question is asked.
    public var lastDayAnchorCandidate: CalendarDay? {
        guard entryMode == .nextCharge, let cycle else { return nil }
        return lastDayOfMonthAnchor(forNextBillingDate: nextChargeDate, cycle: cycle)
    }

    /// True while the §5.1 question is on screen and unanswered.
    public var needsLastDayAnswer: Bool {
        lastDayAnchorCandidate != nil && lastDayAnswer == nil
    }

    /// The anchor of record the form would store - nil while the last-day
    /// question is unanswered.
    public var resolvedAnchor: CalendarDay? {
        switch entryMode {
        case .startDate:
            return startDate
        case .nextCharge:
            guard let candidate = lastDayAnchorCandidate else { return nextChargeDate }
            switch lastDayAnswer {
            case .lastDayOfMonth: return candidate
            case .enteredDay: return nextChargeDate
            case nil: return nil
            }
        }
    }

    /// The trial as currently described, or nil when the toggle is off or the
    /// values are impossible. Conversion and cancel-by dates are its derived
    /// properties - shown live, never entered.
    public var draftTrial: TrialTerm? {
        guard isTrial else { return nil }
        return TrialTerm(
            id: trialID,
            startDate: trialStartDate,
            lengthDays: trialLengthDays,
            bufferDays: trialBufferDays,
            convertsToAmountCents: amountCents ?? 0,
            createdAt: trialCreatedAt,
            updatedAt: dates.now()
        )
    }

    public var trialConversionDate: CalendarDay? { draftTrial?.conversionDate }
    public var trialCancelByDate: CalendarDay? { draftTrial?.cancelByDate }

    /// Spec §6.2 (v1.4): a lead at least one whole cycle long means the user is
    /// permanently warned about the charge AFTER next - nearly always a mistake.
    /// The form warns; it does not block, because the configuration is legal.
    public var leadCoversWholeCycle: Bool {
        guard let cycle else { return false }
        return cycle.isCovered(byLeadDays: reminderLeadDays)
    }

    // MARK: - Validation and building

    public var canSave: Bool {
        buildSubscription() != nil
    }

    /// The domain value the form describes, or nil while it is incomplete: no
    /// name, no valid amount, an unanswered last-day question, or an impossible
    /// trial.
    public func buildSubscription() -> Subscription? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let amountCents,
              let cycle,
              let anchor = resolvedAnchor
        else { return nil }
        if isTrial && draftTrial == nil { return nil }

        let now = dates.now()
        return Subscription(
            id: newID,
            name: trimmedName,
            vendorURL: nonEmptyURL(from: vendorURLText),
            category: category,
            status: status,
            amountCents: amountCents,
            currencyCode: original?.currencyCode ?? "CAD",
            cycle: cycle,
            cycleStartDay: anchor,
            reminderLeadDays: reminderLeadDays,
            sameDayReminder: sameDayReminder,
            pauseEndsOn: original?.pauseEndsOn,
            trial: preservedTrial,
            paymentMethodID: paymentMethodID,
            cancellationURL: nonEmptyURL(from: cancellationURLText),
            cancellationNotes: nonEmpty(cancellationNotes),
            lastUsedDate: original?.lastUsedDate,
            notes: nonEmpty(notes),
            createdAt: original?.createdAt ?? now,
            updatedAt: now,
            deletedAt: original?.deletedAt
        )
    }

    /// The trial the built subscription carries. The toggle governs a live
    /// trial; a NON-`.trial` subscription's term is history - a confirmed
    /// conversion keeps its term deliberately (spec §5.2a: confirming records,
    /// never deletes) - and the toggle the form shows as off must not silently
    /// delete it on an unrelated edit.
    private var preservedTrial: TrialTerm? {
        if let draftTrial { return draftTrial }
        if let original, original.status != .trial { return original.trial }
        return nil
    }

    /// The status the form writes: the trial toggle decides between trial and
    /// active, and every other lifecycle state is preserved - Add/Edit describes
    /// the subscription, it does not run the cancellation or pause flows.
    private var status: SubscriptionStatus {
        switch original?.status {
        case nil, .trial, .active:
            return isTrial ? .trial : .active
        case .paused, .cancellationPending, .cancelled, .archived:
            // Force-unwrap-free by construction: this branch only matches non-nil.
            return original?.status ?? .active
        }
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func nonEmptyURL(from text: String) -> URL? {
        guard let trimmed = nonEmpty(text) else { return nil }
        return URL(string: trimmed)
    }
}
