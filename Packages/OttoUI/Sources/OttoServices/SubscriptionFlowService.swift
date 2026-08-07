import Foundation
import OttoDomain
import OttoRepositories

/// What starting a cancellation produced: the watching record, and the stored
/// URL the UI opens (Otto never cancels anything itself - it opens the page and
/// records what the user tells it).
public struct CancellationStart: Hashable, Sendable {
    public let record: CancellationRecord
    public let cancellationURL: URL?

    public init(record: CancellationRecord, cancellationURL: URL?) {
        self.record = record
        self.cancellationURL = cancellationURL
    }
}

/// The Wave 5 flows' state work - trial confirmation, cancellation, verification -
/// in ONE place, so the notification actions and the screens produce identical
/// state by construction rather than by parallel implementations kept honest by
/// tests alone (the tests exist too).
///
/// Every method is safe to run twice: notification actions get redelivered, users
/// double-tap, and the app can be killed mid-flow, so each method re-derives what
/// remains to be done from stored state and completes exactly that. Decisions
/// live in the domain; this actor loads, calls, and saves. Scheduling is the
/// caller's follow-up - state first, then a reschedule reflects it.
public actor SubscriptionFlowService {

    private let subscriptions: any SubscriptionRepository
    private let cancellations: any CancellationRepository
    private let billingEvents: any BillingEventRepository
    private let priceChanges: any PriceChangeRepository

    public init(
        subscriptions: any SubscriptionRepository,
        cancellations: any CancellationRepository,
        billingEvents: any BillingEventRepository,
        priceChanges: any PriceChangeRepository
    ) {
        self.subscriptions = subscriptions
        self.cancellations = cancellations
        self.billingEvents = billingEvents
        self.priceChanges = priceChanges
    }

    // MARK: - "Keeping it"

    /// Acknowledges the charge this cycle's reminders point at - the earliest
    /// still-expected event on or after today (spec §6.4, §5.3 v1.4). The planner
    /// honours the persisted acknowledgement, so the silencing survives every
    /// subsequent reschedule; the next cycle's event is a different row and
    /// reminds normally. Redelivery keeps the FIRST acknowledgement instant.
    public func acknowledgeCurrentCharge(
        subscriptionID: UUID,
        now: Date,
        today: CalendarDay
    ) async throws {
        let target = try await billingEvents.events(forSubscription: subscriptionID)
            .filter { $0.state == .upcoming && $0.expectedDate >= today }
            .min { $0.expectedDate < $1.expectedDate }
        guard var event = target, event.acknowledgedAt == nil else { return }
        event.acknowledgedAt = now
        event.updatedAt = now
        try await billingEvents.save(event)
    }

    // MARK: - Confirming a trial conversion

    /// The user confirmed they know the trial converted (spec §5.2a, §7.1):
    /// acknowledge the conversion charge's ledger row (the record of "I noticed",
    /// however late), append the price transition, and persist the status flip
    /// the derivation already made. Nothing is deleted - the trial term, the
    /// ledger row, and the price history all remain.
    ///
    /// Ordered so a kill mid-flow heals on re-run: the flip is LAST, because it
    /// is the step that makes the whole method a no-op afterwards.
    public func confirmTrialConversion(
        subscriptionID: UUID,
        now: Date,
        today: CalendarDay
    ) async throws {
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID),
              let flipped = subscription.confirmingConversion(asOf: today, at: now),
              let trial = subscription.trial
        else { return }

        // The record of "I noticed" goes on the conversion charge's own row -
        // acknowledging the NEXT upcoming charge instead would silence a renewal
        // reminder the user never asked to silence.
        let conversionRows = try await billingEvents.eventsIncludingDeleted(forSubscription: subscriptionID)
            .filter { $0.expectedDate == trial.conversionDate }
        if var event = conversionRows.first(where: { $0.deletedAt == nil }) {
            if event.acknowledgedAt == nil {
                event.acknowledgedAt = now
                event.updatedAt = now
                try await billingEvents.save(event)
            }
        } else if !conversionRows.contains(where: { $0.state != .upcoming }) {
            // A trial that converts while the app is closed has no conversion
            // row: §5.3 materializes from `today` forward, and by the first pass
            // the conversion is already behind it - the founding scenario, again.
            // Create the row retrospectively so the acknowledgement (and later
            // verification or a price mismatch) has somewhere to live. Tombstoned
            // non-.upcoming rows on the date mean deliberate removal and win.
            try await billingEvents.save(BillingEvent(
                id: UUID(),
                subscriptionID: subscriptionID,
                expectedDate: trial.conversionDate,
                expectedAmountCents: trial.convertsToAmountCents,
                state: .upcoming,
                acknowledgedAt: now,
                createdAt: now,
                updatedAt: now
            ))
        }

        if subscription.amountCents != trial.convertsToAmountCents {
            let history = try await priceChanges.history(forSubscription: subscriptionID)
            if !history.contains(where: { $0.source == .trialConversion }) {
                try await priceChanges.append(PriceChange(
                    id: UUID(),
                    subscriptionID: subscriptionID,
                    effectiveDate: trial.conversionDate,
                    oldAmountCents: subscription.amountCents,
                    newAmountCents: trial.convertsToAmountCents,
                    source: .trialConversion,
                    createdAt: now,
                    updatedAt: now
                ))
            }
        }

        try await subscriptions.save(flipped)
    }

    // MARK: - Pausing and resuming

    /// Pauses billing (spec §5.1): status `.paused`, the freeze point recorded
    /// (`pausedOn` - the day §5.1's paused-spend price freezes at), and the
    /// resume date stored when the vendor gave one. Only an effectively active
    /// subscription pauses - an unconverted trial has nothing to pause, and the
    /// §5.2a derive-before-you-mutate rule means a converted-unflipped trial
    /// gets its conversion written through FIRST, so the paused record carries
    /// the paid anchor and amount rather than the trial-era ones the status
    /// overwrite would strand.
    public func pause(
        subscriptionID: UUID,
        resumesOn: CalendarDay?,
        now: Date,
        today: CalendarDay
    ) async throws {
        guard var subscription = try await subscriptions.subscription(withID: subscriptionID),
              subscription.effectiveStatus(asOf: today) == .active
        else { return }
        if subscription.isConvertedTrial(asOf: today) {
            try await confirmTrialConversion(subscriptionID: subscriptionID, now: now, today: today)
            guard let flipped = try await subscriptions.subscription(withID: subscriptionID) else { return }
            subscription = flipped
        }
        guard subscription.status != .paused else { return }
        subscription.status = .paused
        subscription.pausedOn = today
        subscription.pauseEndsOn = resumesOn
        subscription.updatedAt = now
        try await subscriptions.save(subscription)
    }

    /// Resumes billing: status `.active`, both pause fields cleared. Also the
    /// manual path out of an indefinite pause - the frozen watermark then
    /// backfills the gap on the next scheduler pass (spec §5.3, v1.6). Accepts
    /// a derived-resumed pause too: persisting what the derivation already
    /// decided is an optimisation, never the mechanism (spec §5.2a).
    public func resume(subscriptionID: UUID, now: Date) async throws {
        guard var subscription = try await subscriptions.subscription(withID: subscriptionID),
              subscription.status == .paused
        else { return }
        subscription.status = .active
        subscription.pauseEndsOn = nil
        subscription.pausedOn = nil
        subscription.updatedAt = now
        try await subscriptions.save(subscription)
    }

    // MARK: - The cancellation flow

    /// Marks the subscription cancelling and creates the watching record
    /// (spec §5.4): status to `.cancellationPending`, the check date computed
    /// exactly once from the trial-aware would-be sequence, the evidence captured
    /// if offered. Returns what the UI needs - the record and the stored
    /// cancellation URL - or nil when the subscription no longer exists.
    ///
    /// Order matters for crash-safety: the record is created BEFORE the status
    /// flips, because `.cancellationPending` without a record is the §5.2b
    /// invariant violation, while a record beside a still-active subscription is
    /// merely dormant. Either interruption point heals on re-run.
    public func startCancellation(
        subscriptionID: UUID,
        evidenceNote: String? = nil,
        now: Date,
        today: CalendarDay
    ) async throws -> CancellationStart? {
        guard var subscription = try await subscriptions.subscription(withID: subscriptionID) else {
            return nil
        }
        let url = subscription.cancellationURL

        var record: CancellationRecord
        if let existing = try await cancellations.record(forSubscription: subscriptionID) {
            record = existing
            // Redelivery never blanks or overwrites captured evidence; the UI's
            // deliberate edits go through updateCancellationEvidence.
            if let evidenceNote, record.evidenceNote == nil {
                record.evidenceNote = evidenceNote
                record.updatedAt = now
                try await cancellations.save(record)
            }
        } else {
            // Date and amount are both derived here, from the PRE-mutation
            // subscription (§5.2a v1.5: derive before you mutate), because both
            // are unrecoverable later - the amount's only other home is the
            // price field a later edit overwrites (spec §5.4, v1.5).
            //
            // Cancelling an INDEFINITELY paused subscription yields no date at
            // all (spec §5.4, v1.5): the check is deferred, never fabricated -
            // the record waits in .awaitingResumeDate until the user supplies
            // the resume date through supplyPausedResumeDate.
            let checkDate = verificationCheckDate(for: subscription, asOf: today)
            record = CancellationRecord(
                id: UUID(),
                subscriptionID: subscriptionID,
                markedCancelledAt: now,
                nextChargeDateIfNotCancelled: checkDate,
                expectedChargeAmountCents: checkDate.map {
                    wouldBeChargeAmountCents(on: $0, for: subscription)
                },
                verificationState: checkDate == nil ? .awaitingResumeDate : .pending,
                evidenceNote: evidenceNote,
                createdAt: now,
                updatedAt: now
            )
            try await cancellations.save(record)
        }

        if subscription.status != .cancellationPending && subscription.status != .cancelled
            && subscription.status != .archived {
            subscription.status = .cancellationPending
            subscription.updatedAt = now
            try await subscriptions.save(subscription)
        }
        return CancellationStart(record: record, cancellationURL: url)
    }

    /// The user supplied the resume date a deferred verification was waiting on
    /// (spec §5.4, v1.5): the check date becomes the first would-be charge on or
    /// after it, and the record joins the ordinary pending watch. Idempotent -
    /// a record no longer awaiting its date is left alone, so a double-tap
    /// cannot overwrite a check already rolling forward.
    public func supplyPausedResumeDate(
        subscriptionID: UUID,
        resumeDate: CalendarDay,
        now: Date
    ) async throws {
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID),
              let record = try await cancellations.record(forSubscription: subscriptionID)
        else { return }
        let supplied = record.supplyingResumeDate(resumeDate, for: subscription, at: now)
        if supplied != record {
            try await cancellations.save(supplied)
        }
    }

    /// Replaces the record's evidence note - the user coming back from the vendor
    /// page with a confirmation number, or correcting an earlier note. A nil or
    /// empty note clears it deliberately.
    public func updateCancellationEvidence(
        subscriptionID: UUID,
        note: String?,
        now: Date
    ) async throws {
        guard var record = try await cancellations.record(forSubscription: subscriptionID) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard record.evidenceNote != newValue else { return }
        record.evidenceNote = newValue
        record.updatedAt = now
        try await cancellations.save(record)
    }

    // MARK: - The verification flow

    /// The user answered "did the charge stop?" (spec §5.4).
    ///
    /// Yes: the record verifies and the subscription archives - the lifecycle's
    /// actual end, the money confirmed stopped. Returns nil.
    ///
    /// No: the record flips to `.stillCharging`, the charge that arrived gets its
    /// retrospective `.unexpectedCharge` ledger row - created at most once, this
    /// being that state's only producer (spec §5.3) - and the dispute summary
    /// comes back for the UI to surface.
    public func answerVerification(
        subscriptionID: UUID,
        chargesStopped: Bool,
        now: Date,
        today: CalendarDay
    ) async throws -> DisputeSummary? {
        guard var subscription = try await subscriptions.subscription(withID: subscriptionID),
              let record = try await cancellations.record(forSubscription: subscriptionID),
              // A deferred check has never watched a date, so there is nothing
              // to answer - and the yes-path must not archive an unverified
              // cancellation (spec §5.4: not archived until verification passes).
              record.verificationState != .awaitingResumeDate
        else { return nil }

        if chargesStopped {
            let verified = record.confirmingChargesStopped(at: now)
            if verified != record {
                try await cancellations.save(verified)
            }
            if subscription.status != .archived {
                subscription.status = .archived
                subscription.updatedAt = now
                try await subscriptions.save(subscription)
            }
            return nil
        }

        let disputed = record.reportingStillCharging(at: now)
        if disputed != record {
            try await cancellations.save(disputed)
        }
        // A deferred check refuses the transition and keeps a nil date; there is
        // no charge to record and nothing to dispute yet.
        guard let chargeDay = disputed.nextChargeDateIfNotCancelled else { return nil }
        let existing = try await billingEvents.events(forSubscription: subscriptionID)
        if !existing.contains(where: { $0.state == .unexpectedCharge && $0.expectedDate == chargeDay }) {
            try await billingEvents.save(BillingEvent(
                id: UUID(),
                subscriptionID: subscriptionID,
                expectedDate: chargeDay,
                // The amount stored at cancellation, like the date (spec §5.4,
                // v1.5); derivation only for pre-v1.5 records never backfilled.
                expectedAmountCents: disputed.expectedChargeAmountCents
                    ?? wouldBeChargeAmountCents(on: chargeDay, for: subscription),
                state: .unexpectedCharge,
                createdAt: now,
                updatedAt: now
            ))
        }
        return disputeSummary(for: disputed, subscription: subscription)
    }
}
