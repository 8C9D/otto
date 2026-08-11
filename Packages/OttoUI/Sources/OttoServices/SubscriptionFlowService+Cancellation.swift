import Foundation
import OttoDomain
import OttoRepositories

// The §5.4 cancellation and verification flows. Split out of
// SubscriptionFlowService.swift, which passed SwiftLint's 400-line
// file_length once F11's boundary logging landed; the seam is the lifecycle
// these methods share - open a watch, close it, answer what it watched for -
// against the trial/pause/usage edits left behind.

extension SubscriptionFlowService {

    /// Marks the subscription cancelling and opens the watching episode
    /// (spec §5.4, §5.3a): status to `.cancellationPending`, the check date and
    /// amount computed exactly once from the pre-mutation subscription
    /// (`openingCancellationEpisode` - §5.2a's derive-before-you-mutate), the
    /// interrupted status recorded for the un-cancel, the evidence captured if
    /// offered. Returns what the UI needs - the episode and the stored
    /// cancellation URL - or nil when the subscription no longer exists or its
    /// lifecycle is already past cancellation.
    ///
    /// Order matters for crash-safety: the episode is opened BEFORE the status
    /// flips, because `.cancellationPending` without an episode is the §5.2b
    /// invariant violation, while an open episode beside a still-active
    /// subscription is merely dormant. Either interruption point heals on
    /// re-run - including the mirror-image interruption, an un-cancel killed
    /// between closing its episode and restoring the status, which this flow
    /// finishes first so the new episode derives from the true state.
    public func startCancellation(
        subscriptionID: UUID,
        evidenceNote: String? = nil,
        now: Date,
        today: CalendarDay
    ) async throws -> CancellationStart? {
        guard var subscription = try await subscriptions.subscription(withID: subscriptionID) else {
            // F11: every exit from this flow says which one it was. A
            // cancellation that quietly did nothing looked, from every surface
            // outside this actor, exactly like one that opened a watch.
            OttoLog.flows.notice("""
                cancellation refused reason=noSubscription \
                id=\(subscriptionID.uuidString, privacy: .public)
                """)
            return nil
        }
        let url = subscription.cancellationURL

        var episode: CancellationEpisode
        if let existing = try await cancellations.openEpisode(forSubscription: subscriptionID) {
            episode = existing
            // Redelivery never blanks or overwrites captured evidence; the UI's
            // deliberate edits go through the evidence methods below. A note is
            // only added when the episode has none, so a redelivered start
            // cannot duplicate the capture.
            if let evidenceNote, episode.liveEvidenceNotes.isEmpty {
                episode.evidenceNotes.append(EvidenceNote(
                    id: UUID(), text: evidenceNote, createdAt: now, updatedAt: now
                ))
                episode.updatedAt = now
                try await cancellations.save(episode)
            }
        } else {
            if subscription.effectiveStatus(asOf: today) == .cancellationPending
                || subscription.effectiveStatus(asOf: today) == .cancelled {
                // Cancelling-with-no-open-episode is an un-cancel that died
                // between its two writes: complete the restore, then cancel
                // from the restored truth.
                let lastAbandoned = try await cancellations.episodes(forSubscription: subscriptionID)
                    .first { $0.outcome == .abandoned }
                guard let restored = subscription.abandoningCancellation(
                    restoringTo: lastAbandoned?.statusAtStart, at: now
                ) else { return nil }
                try await subscriptions.save(restored)
                subscription = restored
            }
            let evidence = evidenceNote.map {
                EvidenceNote(id: UUID(), text: $0, createdAt: now, updatedAt: now)
            }
            guard let opened = subscription.openingCancellationEpisode(
                id: UUID(), evidence: evidence, asOf: today, at: now
            ) else { return nil }
            episode = opened
            try await cancellations.save(episode)
        }

        if let pending = subscription.markingCancellationPending(at: now) {
            try await subscriptions.save(pending)
        }
        OttoLog.flows.notice("""
            cancellation started id=\(subscriptionID.uuidString, privacy: .public) \
            episode=\(episode.id.uuidString, privacy: .public) \
            checkDay=\(OttoLog.dayText(episode.nextChargeDateIfNotCancelled), privacy: .public)
            """)
        return CancellationStart(record: episode, cancellationURL: url)
    }

    /// The un-cancel (spec §5.4, §5.3a): the open episode closes with
    /// `.abandoned` - never deleted, "I thought I'd cancelled this and hadn't"
    /// is exactly the data this product is about - and the subscription
    /// returns to the status the cancellation interrupted.
    ///
    /// Episode first, then the status restore, so a kill between the two heals
    /// on re-run (the else-branch finds the just-closed episode). The
    /// watermark rewinds to the day before the watched charge date when it has
    /// moved past it (spec §5.3, v1.7's rewind rule): un-cancelling asserts
    /// the vendor was charging all along, so the dates the watch covered must
    /// materialize retroactively. New episodes freeze the watermark for their
    /// whole life (the materializer skips cancellation states), so the rewind
    /// only really moves for data migrated from before the freeze existed.
    public func abandonCancellation(
        subscriptionID: UUID,
        now: Date,
        today: CalendarDay
    ) async throws {
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID) else { return }
        let reference: CancellationEpisode?
        if let open = try await cancellations.openEpisode(forSubscription: subscriptionID),
           let closed = open.abandoning(at: now) {
            try await cancellations.save(closed)
            reference = closed
        } else {
            reference = try await cancellations.episodes(forSubscription: subscriptionID)
                .first { $0.outcome == .abandoned }
        }
        guard let reference,
              let restored = subscription.abandoningCancellation(
                  restoringTo: reference.statusAtStart, at: now
              )
        else { return }
        // The rewind is the explicit device-store operation (spec §5.3, Wave
        // 6B-Prep) and runs BEFORE the status restore: a crash between the two
        // leaves only a regressed watermark, the harmless direction. Rewinding
        // is a min(), so a watermark already behind the watched date - or
        // absent - is untouched.
        if let watched = reference.nextChargeDateIfNotCancelled {
            try await billingEvents.rewindMaterializationWatermark(
                forSubscription: subscriptionID, to: watched.adding(days: -1)
            )
        }
        try await subscriptions.save(restored)
        OttoLog.flows.notice("""
            cancellation abandoned id=\(subscriptionID.uuidString, privacy: .public) \
            episode=\(reference.id.uuidString, privacy: .public) \
            rewoundTo=\(OttoLog.dayText(reference.nextChargeDateIfNotCancelled?.adding(days: -1)), privacy: .public)
            """)
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
              let record = try await cancellations.openEpisode(forSubscription: subscriptionID)
        else { return }
        let supplied = record.supplyingResumeDate(resumeDate, for: subscription, at: now)
        if supplied != record {
            try await cancellations.save(supplied)
        }
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
        guard let subscription = try await subscriptions.subscription(withID: subscriptionID),
              let record = try await cancellations.openEpisode(forSubscription: subscriptionID),
              // A deferred check has never watched a date, so there is nothing
              // to answer - and the yes-path must not archive an unverified
              // cancellation (spec §5.4: not archived until verification passes).
              record.verificationState != .awaitingResumeDate
        else {
            OttoLog.flows.notice("""
                verification refused reason=noOpenAnswerableEpisode \
                id=\(subscriptionID.uuidString, privacy: .public)
                """)
            return nil
        }

        if chargesStopped {
            let verified = record.confirmingChargesStopped(at: now)
            if verified != record {
                try await cancellations.save(verified)
            }
            let archived = subscription.archiving(at: now)
            if let archived {
                try await subscriptions.save(archived)
            }
            // The lifecycle's actual end - the money confirmed stopped - and
            // until now the only boundary in the app that ended a subscription
            // without writing anything down.
            OttoLog.flows.notice("""
                verification answered chargesStopped=true \
                id=\(subscriptionID.uuidString, privacy: .public) \
                archived=\(archived != nil, privacy: .public)
                """)
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
        OttoLog.flows.notice("""
            verification answered chargesStopped=false \
            id=\(subscriptionID.uuidString, privacy: .public) \
            disputedDay=\(OttoLog.dayText(chargeDay), privacy: .public)
            """)
        return disputeSummary(for: disputed, subscription: subscription)
    }
}
