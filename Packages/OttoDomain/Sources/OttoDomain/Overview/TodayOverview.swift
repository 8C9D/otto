import Foundation

/// One subscription's entry in the Today overview: the single date that matters
/// for it right now, and why.
public struct TodayEntry: Hashable, Sendable, Identifiable {
    public enum Reason: Hashable, Sendable {
        /// The trial is inside its cancel-by window - or its conversion date has
        /// passed while the status still says trial, which equally needs a human.
        case trialActionNeeded
        /// A verification check date has arrived with no answer: did the money stop?
        case verificationDue
        /// The user reported a charge after cancelling - the dispute case (spec §5.4).
        case verificationFailed
        /// An ordinary expected charge.
        case upcomingCharge(amountCents: Int)
        /// The trial converts to paid on `date` - not yet inside the action window.
        case trialConverts(amountCents: Int)
        /// A paused subscription resumes billing on `date` (spec §5.1).
        case pauseResumes
        /// A verification check scheduled for `date`, still ahead.
        case verificationCheck
    }

    public let subscription: Subscription
    public let reason: Reason

    /// The day this entry keys on - deadline, charge, resume, or check date -
    /// and what the sections sort by.
    public let date: CalendarDay

    /// A subscription produces at most one entry, so its id serves as the entry's.
    public var id: UUID { subscription.id }

    public init(subscription: Subscription, reason: Reason, date: CalendarDay) {
        self.subscription = subscription
        self.reason = reason
        self.date = date
    }

    /// Whether this entry belongs in Today's *Needs action* section.
    public var needsAction: Bool {
        switch reason {
        case .trialActionNeeded, .verificationDue, .verificationFailed: true
        case .upcomingCharge, .trialConverts, .pauseResumes, .verificationCheck: false
        }
    }
}

/// The Today screen's three sections (spec §7.1), derived as a pure function of the
/// data and the day - the view renders this, it never classifies.
///
/// **Needs action** holds the items waiting on the user right now: trials inside
/// their cancel-by window, verification checks whose date has arrived unanswered,
/// and failed verifications. **Next 30 days** and **Later** split every other
/// dated expectation - charges, trial conversions, pause resumes, future
/// verification checks - at thirty days out.
public struct TodayOverview: Hashable, Sendable {
    public var needsAction: [TodayEntry]
    public var next30Days: [TodayEntry]
    public var later: [TodayEntry]

    public init(needsAction: [TodayEntry], next30Days: [TodayEntry], later: [TodayEntry]) {
        self.needsAction = needsAction
        self.next30Days = next30Days
        self.later = later
    }
}

/// Classifies every live subscription into `TodayOverview`'s sections.
///
/// - Parameter cancellations: each subscription's cancellation record, where one
///   exists, keyed by subscription id - it drives the verification entries.
public func todayOverview(
    subscriptions: [Subscription],
    cancellations: [UUID: CancellationRecord],
    from today: CalendarDay
) -> TodayOverview {
    let entries = subscriptions
        .filter { $0.deletedAt == nil }
        .compactMap { todayEntry(for: $0, cancellation: cancellations[$0.id], from: today) }
        .sorted { lhs, rhs in
            (lhs.date, lhs.subscription.name, lhs.id.uuidString)
                < (rhs.date, rhs.subscription.name, rhs.id.uuidString)
        }

    let horizon = today.adding(days: 30)
    return TodayOverview(
        needsAction: entries.filter(\.needsAction),
        next30Days: entries.filter { !$0.needsAction && $0.date <= horizon },
        later: entries.filter { !$0.needsAction && $0.date > horizon }
    )
}

/// One subscription's single entry - the same classification `todayOverview` uses,
/// exposed on its own because the subscription list's "next date" column is this
/// entry's date, and two derivations of the same fact would eventually disagree.
public func todayEntry(
    for subscription: Subscription,
    cancellation: CancellationRecord?,
    from today: CalendarDay
) -> TodayEntry? {
    switch subscription.status {
    case .trial:
        return trialEntry(for: subscription, today: today)

    case .active:
        // Includes a charge landing today: it is still worth knowing about.
        let next = nextBillingDate(
            after: today.adding(days: -1), anchor: subscription.cycleStartDay, cycle: subscription.cycle
        )
        return TodayEntry(
            subscription: subscription,
            reason: .upcomingCharge(amountCents: subscription.amountCents),
            date: next
        )

    case .paused:
        guard let resumes = subscription.pauseEndsOn, resumes >= today else { return nil }
        return TodayEntry(subscription: subscription, reason: .pauseResumes, date: resumes)

    case .cancellationPending, .cancelled:
        return verificationEntry(for: subscription, cancellation: cancellation, today: today)

    case .archived:
        return nil
    }
}

private func trialEntry(for subscription: Subscription, today: CalendarDay) -> TodayEntry? {
    // A trial-status subscription with no trial term has no dates to classify
    // by; the reminder planner and the materializer skip it the same way.
    guard let trial = subscription.trial else { return nil }
    // The action window opens when the trial's reminders do - lead days ahead
    // of the cancel-by date - and stays open through conversion: past cancel-by
    // is a last call, not a lost cause.
    let windowOpens = trial.cancelByDate.adding(days: -subscription.reminderLeadDays)
    if today < windowOpens {
        return TodayEntry(
            subscription: subscription,
            reason: .trialConverts(amountCents: trial.convertsToAmountCents),
            date: trial.conversionDate
        )
    }
    // Inside the window - or past conversion while the status still says trial,
    // which is a state only the user can resolve (Wave 5 owns the recorded
    // transition), so it stays a card rather than vanishing.
    return TodayEntry(subscription: subscription, reason: .trialActionNeeded, date: trial.cancelByDate)
}

private func verificationEntry(
    for subscription: Subscription,
    cancellation: CancellationRecord?,
    today: CalendarDay
) -> TodayEntry? {
    guard let record = cancellation, record.deletedAt == nil else {
        // Cancelled with no record: the check date is unknowable, and only the
        // user can supply it - surfaced today rather than silently unwatched.
        return TodayEntry(subscription: subscription, reason: .verificationDue, date: today)
    }
    switch record.verificationState {
    case .stillCharging:
        return TodayEntry(
            subscription: subscription, reason: .verificationFailed, date: record.nextChargeDateIfNotCancelled
        )
    case .pending where record.nextChargeDateIfNotCancelled <= today:
        // The check date arrived unanswered. It stays a card until answered -
        // §5.4's roll-forward and three-cycle cap govern notifications (Wave 5),
        // not this section.
        return TodayEntry(
            subscription: subscription, reason: .verificationDue, date: record.nextChargeDateIfNotCancelled
        )
    case .pending:
        return TodayEntry(
            subscription: subscription, reason: .verificationCheck, date: record.nextChargeDateIfNotCancelled
        )
    case .verifiedStopped:
        // Resolved; archiving is a Wave 5 flow, and there is nothing to show here.
        return nil
    }
}
