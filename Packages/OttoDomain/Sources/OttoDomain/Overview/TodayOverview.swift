import Foundation

/// One subscription's entry in the Today overview: the single date that matters
/// for it right now, and why.
public struct TodayEntry: Hashable, Sendable, Identifiable {
    public enum Reason: Hashable, Sendable {
        /// The trial is inside its cancel-by window: the deadline is ahead and the
        /// user can still act for free.
        case trialActionNeeded
        /// The trial converted (spec §5.2a) and the user has never confirmed they
        /// know: money is moving. This is the case the app exists for, and it stays
        /// in Needs action indefinitely - it does not get to scroll away (spec §7.1).
        case trialConverted(amountCents: Int)
        /// A verification check date has arrived with no answer: did the money stop?
        case verificationDue
        /// The user reported a charge after cancelling - the dispute case (spec §5.4).
        case verificationFailed
        /// A §5.2b invariant is violated - a cancellation state with no record to
        /// watch it. The state should not exist; when it does, the user must see it
        /// rather than the app quietly deciding for them (spec §7.1).
        case needsReview
        /// An indefinitely paused subscription was cancelled and its verification
        /// is deferred (spec §5.4, v1.5): Otto needs the resume date the vendor
        /// gave, because it will not fabricate one. Needs action until supplied.
        case verificationNeedsResumeDate
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
        case .trialActionNeeded, .trialConverted, .verificationDue, .verificationFailed,
             .needsReview, .verificationNeedsResumeDate: true
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
    // Conversion is derived, never awaited (spec §5.2a): a converted trial is
    // classified here, before the status switch, because its stored status still
    // says .trial while its effective status is .active - and what the user needs
    // to see is neither an ordinary charge row nor a cancel-by deadline, but the
    // fact that money started moving.
    if subscription.isConvertedTrial(asOf: today), let trial = subscription.trial {
        return TodayEntry(
            subscription: subscription,
            reason: .trialConverted(amountCents: trial.convertsToAmountCents),
            date: trial.conversionDate
        )
    }

    switch subscription.effectiveStatus(asOf: today) {
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
    // Unreachable for a live value (§5.2b makes .trial-without-term unconstructible),
    // but this function cannot prove its caller checked.
    guard let trial = subscription.trial else { return nil }
    // The action window opens when the trial's reminders do - lead days ahead
    // of the cancel-by date - and stays open through the day before conversion:
    // past cancel-by is a last call, not a lost cause. Conversion itself is
    // classified before the status switch (spec §5.2a).
    let windowOpens = trial.cancelByDate.adding(days: -subscription.reminderLeadDays)
    if today < windowOpens {
        return TodayEntry(
            subscription: subscription,
            reason: .trialConverts(amountCents: trial.convertsToAmountCents),
            date: trial.conversionDate
        )
    }
    return TodayEntry(subscription: subscription, reason: .trialActionNeeded, date: trial.cancelByDate)
}

private func verificationEntry(
    for subscription: Subscription,
    cancellation: CancellationRecord?,
    today: CalendarDay
) -> TodayEntry? {
    guard let record = cancellation, record.deletedAt == nil else {
        // A cancellation state with no record is a §5.2b invariant violation: the
        // subscription is unwatched, which is Failure B with extra steps. Rendered
        // as needs-review, dated today, rather than as an ordinary due item -
        // the state should not exist, and the user must see that it does.
        return TodayEntry(subscription: subscription, reason: .needsReview, date: today)
    }
    switch record.verificationState {
    case .awaitingResumeDate:
        // The deferred check (spec §5.4, v1.5): no date exists yet and none is
        // fabricated - the card asks for the one the vendor gave, dated today
        // because it is waiting on the user, not the calendar.
        return TodayEntry(subscription: subscription, reason: .verificationNeedsResumeDate, date: today)
    case .stillCharging, .needsManualReview, .pending:
        // Every one of these states carries its check date by construction; a
        // record that lost it anyway is the same failure as a missing record -
        // unwatched - and surfaces the same way.
        guard let checkDate = record.nextChargeDateIfNotCancelled else {
            return TodayEntry(subscription: subscription, reason: .needsReview, date: today)
        }
        switch record.verificationState {
        case .stillCharging:
            return TodayEntry(subscription: subscription, reason: .verificationFailed, date: checkDate)
        case .needsManualReview:
            // Three checks ignored (spec §5.4): notifications stopped, and this
            // card is the escalation - persistent until the user answers.
            return TodayEntry(subscription: subscription, reason: .verificationDue, date: checkDate)
        default:
            // The check date arrived unanswered stays a card until answered -
            // §5.4's roll-forward and three-cycle cap govern notifications
            // (Wave 5), not this section. A future date is an upcoming check.
            let reason: TodayEntry.Reason = checkDate <= today ? .verificationDue : .verificationCheck
            return TodayEntry(subscription: subscription, reason: reason, date: checkDate)
        }
    case .verifiedStopped:
        // Resolved; archiving is a Wave 5 flow, and there is nothing to show here.
        return nil
    }
}
