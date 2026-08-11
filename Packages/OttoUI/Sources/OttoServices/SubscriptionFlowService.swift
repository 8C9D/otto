import Foundation
import OttoDomain
import OttoRepositories

/// What starting a cancellation produced: the watching record, and the stored
/// URL the UI opens (Otto never cancels anything itself - it opens the page and
/// records what the user tells it).
public struct CancellationStart: Hashable, Sendable {
    public let record: CancellationEpisode
    public let cancellationURL: URL?

    public init(record: CancellationEpisode, cancellationURL: URL?) {
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

    // fileprivate would be tighter, but the evidence methods and the §5.4
    // cancellation/verification flows live in same-module extension files;
    // internal is the narrowest level that reaches them. `private` is
    // file-scoped, and the split those files came from is deliberate - see
    // SubscriptionFlowService+Cancellation.swift.
    let subscriptions: any SubscriptionRepository
    let cancellations: any CancellationRepository
    let billingEvents: any BillingEventRepository
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

    // MARK: - Recording use (spec §7.3)

    /// The user said they used this - from the 90-day check-in notification or
    /// the Detail screen. `lastUsedDate` is what zombie detection counts from;
    /// recording it is a user statement, so `updatedAt` moves. Idempotent per
    /// day: saying it twice on one day is one fact.
    public func recordUsage(subscriptionID: UUID, on today: CalendarDay, now: Date) async throws {
        guard var subscription = try await subscriptions.subscription(withID: subscriptionID),
              subscription.lastUsedDate != today
        else { return }
        subscription.lastUsedDate = today
        subscription.updatedAt = now
        try await subscriptions.save(subscription)
    }

    // MARK: - Pausing and resuming

    /// Pauses billing (spec §5.1, §5.3a): status `.paused` and a new open
    /// `PauseEpisode` opened - its start is the freeze point §7.2's paused-spend
    /// price pins to. Only an effectively active subscription pauses - an
    /// unconverted trial has nothing to pause, and the §5.2a
    /// derive-before-you-mutate rule means a converted-unflipped trial gets its
    /// conversion written through FIRST, so the paused record carries the paid
    /// anchor and amount rather than the trial-era ones the status overwrite
    /// would strand.
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
        guard let paused = subscription.pausing(
            on: today, until: resumesOn, episodeID: UUID(), at: now
        ) else { return }
        try await subscriptions.save(paused)
    }

    /// Resumes billing: status `.active`, and the open episode closed - never
    /// cleared (spec §5.3a: exiting writes an end date). Also the manual path
    /// out of an indefinite pause - the frozen watermark then backfills the gap
    /// on the next scheduler pass (spec §5.3, v1.6). Accepts a derived-resumed
    /// pause too: persisting what the derivation already decided is an
    /// optimisation, never the mechanism (spec §5.2a).
    public func resume(subscriptionID: UUID, now: Date, today: CalendarDay) async throws {
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID),
              let resumed = subscription.resuming(on: today, at: now)
        else { return }
        try await subscriptions.save(resumed)
    }
}
