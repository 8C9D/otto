import Foundation

// The verification flow's decisions (spec §5.4) - the feature no other tracker
// has, kept pure here so the flows above are orchestration only. A cancellation
// is not done until the money is confirmed stopped, and nothing below may depend
// on the app having been opened at any particular time: every function derives
// from stored state plus a `today` the caller injects (spec §5.2a's principle).

/// After this many consecutive unanswered checks, the record escalates to
/// `.needsManualReview` and stops generating notifications (spec §5.4):
/// notifications are not reaching this item, and a fourth won't either.
public let unansweredCheckLimit = 3

/// The first date a charge would land strictly after `day` if the subscription
/// kept billing - the sequence a cancellation is verified against.
///
/// Trial-aware where `billingAnchor(asOf:)` cannot be: that derivation keys off
/// the stored `.trial` status, which a cancellation has already overwritten. The
/// trial term itself still tells the truth - a trial's paid sequence runs from
/// its conversion date whether the flip was persisted or not, and a persisted
/// flip rebases `cycleStartDay` to the same anchor.
public func nextWouldBeChargeDate(after day: CalendarDay, for subscription: Subscription) -> CalendarDay {
    if let trial = subscription.trial {
        if day < trial.conversionDate { return trial.conversionDate }
        return nextBillingDate(after: day, anchor: trial.conversionDate, cycle: subscription.cycle)
    }
    return nextBillingDate(after: day, anchor: subscription.cycleStartDay, cycle: subscription.cycle)
}

/// The check date a new `CancellationEpisode` stores (spec §5.4): the first
/// occurrence in the billing sequence STRICTLY AFTER the cancellation day.
/// Computed exactly once, at cancellation time, because `markedCancelledAt` is a
/// UTC instant that §4.1 forbids turning into a calendar day later -
/// `cancelledOn` is that instant already converted, by the caller, in an
/// explicit timezone.
///
/// Strictly after, never on-or-after (Wave 10, defect G): an occurrence ON the
/// cancellation day has already landed legitimately - cancelling a converted
/// trial on its conversion day must watch the NEXT cycle, because "a charge
/// arrived on the day I cancelled" proves nothing about whether the
/// cancellation took, and the dispute summary built from it would be rejected
/// by any bank. `>= today` is an unsafe default anywhere a past occurrence can
/// be a legitimate already-settled event (spec §5.4, v2.6).
///
/// Cancelling a PAUSED subscription (spec §5.4, v1.5) does not watch the plain
/// anchor sequence - the vendor is not charging during the pause, so "no charge
/// arrived" on one of those dates would prove nothing. With a `pauseEndsOn` the
/// check is the first occurrence both on or after it AND strictly after the
/// cancellation day. Without one there is no determinate date, and the answer
/// is NIL: do not guess - a verification answered against a fabricated date
/// produces false confidence in exactly the place the product promises
/// certainty. The caller defers the check (`.awaitingResumeDate`) until the
/// user supplies a resume date.
public func verificationCheckDate(
    for subscription: Subscription, cancelledOn cancellationDay: CalendarDay
) -> CalendarDay? {
    if subscription.effectiveStatus(asOf: cancellationDay) == .paused {
        guard let resumes = subscription.pauseEndsOn else { return nil }
        return nextWouldBeChargeDate(
            after: max(resumes.adding(days: -1), cancellationDay), for: subscription
        )
    }
    return nextWouldBeChargeDate(after: cancellationDay, for: subscription)
}

/// What a would-be charge on `day` would cost. An unflipped trial's stored
/// amount is the trial-era price, so any charge on or after conversion is the
/// converted one; a persisted flip rebases the anchor to the conversion date and
/// carries the converted amount in `amountCents` - the anchor tells which era
/// `amountCents` belongs to, which matters when the user edited the price after
/// conversion.
public func wouldBeChargeAmountCents(on day: CalendarDay, for subscription: Subscription) -> Int {
    if let trial = subscription.trial,
       day >= trial.conversionDate,
       subscription.cycleStartDay != trial.conversionDate {
        return trial.convertsToAmountCents
    }
    return subscription.amountCents
}

// MARK: - Verification transitions

extension CancellationEpisode {
    /// The yes-path: the user confirmed the money stopped, which IS the
    /// episode's end (spec §5.3a: exiting writes an end date; §5.4 v1.9:
    /// reaching this result does not set a state, it closes the episode with
    /// `outcome = .verifiedStopped`) - and the caller archives the subscription
    /// alongside (spec §5.4: not archived until verification passes).
    /// Idempotent - a closed episode keeps its first `verifiedAt` and
    /// `endedAt`. A deferred check cannot be answered: no date was ever
    /// watched, so there is nothing the confirmation would be about. The live
    /// state is left where the watch was; once closed, nothing reads it.
    public func confirmingChargesStopped(at now: Date) -> CancellationEpisode {
        guard isOpen,
              verificationState != .awaitingResumeDate
        else { return self }
        var updated = self
        updated.verifiedAt = now
        updated.endedAt = now
        updated.outcome = .verifiedStopped
        updated.updatedAt = monotonicStamp(now, notBefore: updated.updatedAt)
        return updated
    }

    /// The un-cancel's episode half (spec §5.4, §5.3a): closed with
    /// `.abandoned`, never deleted - a record of "I thought I'd cancelled this
    /// and hadn't" is exactly the data this product is about. The watch state
    /// is left as it was; the outcome says why watching stopped. Nil when the
    /// episode is already closed, which keeps the calling flow idempotent.
    public func abandoning(at now: Date) -> CancellationEpisode? {
        guard isOpen else { return nil }
        var updated = self
        updated.endedAt = now
        updated.outcome = .abandoned
        updated.updatedAt = monotonicStamp(now, notBefore: updated.updatedAt)
        return updated
    }

    /// The no-path: a charge arrived after cancellation - the dispute case.
    /// Idempotent for the same reason. Callers create the retrospective
    /// `.unexpectedCharge` ledger row (spec §5.3: this flow is that state's only
    /// producer). A deferred check cannot be answered - it has no watched date
    /// for the dispute to name.
    public func reportingStillCharging(at now: Date) -> CancellationEpisode {
        guard isOpen,
              verificationState != .stillCharging,
              verificationState != .awaitingResumeDate
        else { return self }
        var updated = self
        updated.verificationState = .stillCharging
        updated.verifiedAt = now
        updated.updatedAt = monotonicStamp(now, notBefore: updated.updatedAt)
        return updated
    }

    /// The roll-forward (spec §5.4): every check date that passed unanswered
    /// increments the counter and moves the watch to the next would-be charge
    /// date; at `unansweredCheckLimit` the record escalates to
    /// `.needsManualReview` and rolls no further. A check dated today is still
    /// answerable today, so only dates strictly behind `today` count.
    ///
    /// One call catches up an arbitrary absence - a phone in a drawer for three
    /// cycles resolves to the same state as three timely scheduler passes - and
    /// running it twice on the same day equals running it once, because after
    /// the first call no check date is behind `today`.
    public func catchingUpOnUnansweredChecks(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at now: Date
    ) -> CancellationEpisode {
        // A deferred check (.awaitingResumeDate) has no date to roll: it is
        // waiting on the user, not on the calendar, and it never escalates.
        // A closed episode stopped watching when it ended (spec §5.3a) - an
        // abandoned cancellation must not keep rolling toward escalation.
        guard isOpen,
              verificationState == .pending,
              var watchedDate = nextChargeDateIfNotCancelled
        else { return self }
        var updated = self
        // Records written before v1.5 carry no amount; the roll-forward is the
        // standing pass that touches every pending record, so it backfills here -
        // computed by the same rule the flow uses, then stored like the date.
        if updated.expectedChargeAmountCents == nil {
            updated.expectedChargeAmountCents = wouldBeChargeAmountCents(
                on: watchedDate, for: subscription
            )
        }
        while watchedDate < today && updated.unansweredCheckCount < unansweredCheckLimit {
            updated.unansweredCheckCount += 1
            watchedDate = nextWouldBeChargeDate(after: watchedDate, for: subscription)
            updated.nextChargeDateIfNotCancelled = watchedDate
            // The watched amount moves with the watched date (spec §5.4, v1.5).
            updated.expectedChargeAmountCents = wouldBeChargeAmountCents(
                on: watchedDate, for: subscription
            )
        }
        if updated.unansweredCheckCount >= unansweredCheckLimit {
            updated.verificationState = .needsManualReview
        }
        guard updated != self else { return self }
        updated.updatedAt = monotonicStamp(now, notBefore: updated.updatedAt)
        return updated
    }

    /// The user supplied the resume date a deferred check was waiting on
    /// (spec §5.4, v1.5; Wave 7): the watch starts at the first would-be charge
    /// on or after it - the same rule a `pauseEndsOn` cancellation uses - and
    /// the record becomes an ordinary pending verification. Idempotent: only a
    /// record still awaiting its date changes.
    public func supplyingResumeDate(
        _ resumeDate: CalendarDay,
        for subscription: Subscription,
        at now: Date
    ) -> CancellationEpisode {
        guard isOpen, verificationState == .awaitingResumeDate else { return self }
        let checkDate = nextWouldBeChargeDate(after: resumeDate.adding(days: -1), for: subscription)
        var updated = self
        updated.nextChargeDateIfNotCancelled = checkDate
        updated.expectedChargeAmountCents = wouldBeChargeAmountCents(on: checkDate, for: subscription)
        updated.verificationState = .pending
        updated.updatedAt = monotonicStamp(now, notBefore: updated.updatedAt)
        return updated
    }
}

// MARK: - The dispute summary

/// Everything a bank dispute needs, in one value (spec §5.4, §7.1 screen 6):
/// when the cancellation was performed, the evidence captured then, and the
/// charge that arrived anyway. The UI renders it readable-aloud; the facts are
/// assembled here so both the screen and the notification path agree on them.
public struct DisputeSummary: Hashable, Sendable {
    public let subscriptionName: String
    /// When the user performed the cancellation - a UTC instant, displayed in
    /// the user's zone by the UI.
    public let markedCancelledAt: Date
    /// Confirmation numbers, reps' names, screenshot references - every live
    /// note captured during the fight, each with its own date (spec §5.4, a
    /// list since v1.9), oldest first.
    public let evidenceNotes: [EvidenceNote]
    /// The day the disputed charge landed.
    public let chargeDate: CalendarDay
    public let chargeAmountCents: Int
    public let currencyCode: String

    public init(
        subscriptionName: String,
        markedCancelledAt: Date,
        evidenceNotes: [EvidenceNote],
        chargeDate: CalendarDay,
        chargeAmountCents: Int,
        currencyCode: String
    ) {
        self.subscriptionName = subscriptionName
        self.markedCancelledAt = markedCancelledAt
        self.evidenceNotes = evidenceNotes
        self.chargeDate = chargeDate
        self.chargeAmountCents = chargeAmountCents
        self.currencyCode = currencyCode
    }
}

/// The dispute summary for a failed cancellation, or nil while there is nothing
/// to dispute - only a `.stillCharging` record has a charge that arrived.
public func disputeSummary(
    for record: CancellationEpisode,
    subscription: Subscription
) -> DisputeSummary? {
    // Only an OPEN .stillCharging record disputes: a closed episode's dispute
    // was resolved when it ended (spec §5.4 v1.9), and the state always carries
    // its charge date (the nil date belongs to .awaitingResumeDate alone); the
    // guard keeps the function total rather than trusting the invariant.
    guard record.isOpen,
          record.verificationState == .stillCharging,
          let chargeDate = record.nextChargeDateIfNotCancelled
    else { return nil }
    return DisputeSummary(
        subscriptionName: subscription.name,
        markedCancelledAt: record.markedCancelledAt,
        evidenceNotes: record.liveEvidenceNotes,
        chargeDate: chargeDate,
        // The amount stored at cancellation (spec §5.4, v1.5): the summary that
        // ends at a bank contains no heuristics. The derivation is only the
        // fallback for pre-v1.5 records the roll-forward has not yet backfilled.
        chargeAmountCents: record.expectedChargeAmountCents ?? wouldBeChargeAmountCents(
            on: chargeDate, for: subscription
        ),
        currencyCode: subscription.currencyCode
    )
}

// MARK: - Opening an episode

extension Subscription {
    /// The episode `startCancellation` opens (spec §5.4, §5.3a), derived from
    /// the PRE-mutation subscription (§5.2a: derive before you mutate): the
    /// check date and amount are computed exactly once, here, because both are
    /// unrecoverable later - and the interrupted status is recorded alongside,
    /// because it is what an un-cancel restores and the one ambiguity (trial
    /// cancelled before conversion versus confirmed conversion) cannot be
    /// derived back honestly. Lives on the subscription so flows never read
    /// the stored status (spec §5.2a, v1.7).
    ///
    /// Nil when the lifecycle is already at or past cancellation - there is
    /// nothing to interrupt, and a redelivered notification action must not
    /// mint a fresh cancellation for an archived subscription.
    public func openingCancellationEpisode(
        id episodeID: UUID,
        evidence: EvidenceNote?,
        asOf today: CalendarDay,
        at now: Date
    ) -> CancellationEpisode? {
        guard storedStatus == .trial || storedStatus == .active || storedStatus == .paused else {
            return nil
        }
        // Cancelling an INDEFINITELY paused subscription yields no date at all
        // (spec §5.4, v1.5): the check is deferred, never fabricated - the
        // episode waits in .awaitingResumeDate until the user supplies the
        // resume date.
        let checkDate = verificationCheckDate(for: self, cancelledOn: today)
        return CancellationEpisode(
            id: episodeID,
            subscriptionID: id,
            markedCancelledAt: now,
            statusAtStart: storedStatus,
            nextChargeDateIfNotCancelled: checkDate,
            expectedChargeAmountCents: checkDate.map { wouldBeChargeAmountCents(on: $0, for: self) },
            verificationState: checkDate == nil ? .awaitingResumeDate : .pending,
            evidenceNotes: evidence.map { [$0] } ?? [],
            createdAt: now,
            updatedAt: now
        )
    }
}
