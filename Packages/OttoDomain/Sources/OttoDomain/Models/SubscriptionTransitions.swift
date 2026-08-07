import Foundation

// MARK: - Lifecycle transitions (spec §5.1, §5.4)

// The intent-named writes that pair with §5.2a's read rule (v1.7): flows above
// layer 2 cannot touch the stored status, so every persisted transition is a
// domain decision with its guards and side-writes in one place. Each returns
// nil when there is nothing to do, which keeps the calling flows idempotent.
extension Subscription {
    /// Pauses billing (spec §5.1, §5.3a): status `.paused` and a new OPEN
    /// `PauseEpisode` appended - its start is the freeze point §7.2's
    /// paused-spend price pins to, its scheduled resume drives the resume
    /// reminder. The episode id is caller-supplied because the domain mints
    /// nothing (spec §5.0: ids are client-generated, by the flows).
    ///
    /// Only a stored-active subscription pauses: the flow derives and persists
    /// a trial conversion FIRST (§5.2a's derive-before-you-mutate), and a
    /// still-paused one has nothing to re-pause.
    public func pausing(
        on today: CalendarDay,
        until resumesOn: CalendarDay?,
        episodeID: UUID,
        at now: Date
    ) -> Subscription? {
        guard storedStatus == .active else { return nil }
        var updated = self
        updated.storedStatus = .paused
        updated.pauseEpisodes.append(PauseEpisode(
            id: episodeID,
            startedOn: today,
            scheduledResumeOn: resumesOn,
            createdAt: now,
            updatedAt: now
        ))
        updated.updatedAt = now
        return updated
    }

    /// Resumes billing: `.active`, and the open episode CLOSED, never cleared
    /// (spec §5.3a: exiting writes an end date - the pause history is what
    /// makes "what did this cost me last year" answerable). Also the manual
    /// path out of an indefinite pause - the frozen watermark then backfills
    /// the gap on the next scheduler pass (spec §5.3, v1.6). Accepts a
    /// derived-resumed pause too: persisting what the derivation already
    /// decided is an optimisation, never the mechanism (spec §5.2a), and the
    /// episode records the SCHEDULED day as its end in that case, because that
    /// is the day the vendor actually resumed billing.
    public func resuming(on today: CalendarDay, at now: Date) -> Subscription? {
        guard storedStatus == .paused,
              let open = currentPauseEpisode,
              let closed = open.resuming(on: today, at: now),
              let index = pauseEpisodes.firstIndex(where: { $0.id == open.id })
        else { return nil }
        var updated = self
        updated.pauseEpisodes[index] = closed
        updated.storedStatus = .active
        updated.updatedAt = now
        return updated
    }

    /// The status flip of `startCancellation` (spec §5.4). Nil once the
    /// lifecycle is already at or past cancellation, so a redelivered
    /// notification action cannot regress an archived subscription.
    public func markingCancellationPending(at now: Date) -> Subscription? {
        guard storedStatus != .cancellationPending,
              storedStatus != .cancelled,
              storedStatus != .archived
        else { return nil }
        var updated = self
        updated.storedStatus = .cancellationPending
        updated.updatedAt = now
        return updated
    }

    /// The lifecycle's actual end (spec §5.4): verification passed, the money
    /// is confirmed stopped. Nil when already archived.
    ///
    /// An open pause episode stays open deliberately (spec §5.3a): a
    /// subscription cancelled mid-pause died paused - billing never resumed,
    /// and writing a resume day it never had would be fiction.
    public func archiving(at now: Date) -> Subscription? {
        guard storedStatus != .archived else { return nil }
        var updated = self
        updated.storedStatus = .archived
        updated.updatedAt = now
        return updated
    }

    /// The un-cancel (spec §5.4, §5.3a): the status returns to what the
    /// cancellation interrupted. The caller closes the open episode with
    /// `.abandoned` alongside - never deletes it, because "I thought I'd
    /// cancelled this and hadn't" is exactly the data this product is about.
    ///
    /// `statusAtStart` is the episode's recorded pre-cancellation state; the
    /// restore validates it against what the subscription still carries rather
    /// than trusting it blindly, and derives an honest answer when a migrated
    /// pre-8.5 episode recorded nothing:
    /// - `.paused` needs the open pause episode a cancelled-while-paused
    ///   subscription still has (nothing closed it);
    /// - `.trial` needs its term (§5.2b) - a conversion date already past is
    ///   fine, §5.2a's derivation converts it the moment anything asks;
    /// - with no recorded status, an open pause means `.paused`, a trial term
    ///   means `.trial` (a confirmed-converted trial restored this way just
    ///   re-derives to `.active`, converging), and otherwise `.active`.
    ///
    /// Nil unless the lifecycle is at `.cancellationPending` or `.cancelled` -
    /// an archived subscription's cancellation was verified, and un-cancelling
    /// verified history is a different operation this app does not have.
    public func abandoningCancellation(
        restoringTo statusAtStart: SubscriptionStatus?,
        at now: Date
    ) -> Subscription? {
        guard storedStatus == .cancellationPending || storedStatus == .cancelled else { return nil }
        var updated = self
        updated.storedStatus = restoredStatus(from: statusAtStart)
        updated.updatedAt = now
        return updated
    }

    private func restoredStatus(from statusAtStart: SubscriptionStatus?) -> SubscriptionStatus {
        switch statusAtStart {
        case .active:
            return .active
        case .trial:
            return trial != nil ? .trial : .active
        case .paused:
            return currentPauseEpisode != nil ? .paused : .active
        case .cancellationPending, .cancelled, .archived, nil:
            // Nil is a migrated pre-8.5 episode; a recorded status that cannot
            // precede a cancellation is data damage. Both derive the same way.
            if currentPauseEpisode != nil { return .paused }
            if trial != nil { return .trial }
            return .active
        }
    }
}

// MARK: - Record-preserving edits (spec §7.1)

// The Add/Edit form DESCRIBES the subscription; it does not run the pause or
// cancellation flows. These are the two places an edit legitimately depends on
// the stored lifecycle - kept in the domain so the form never reads it.
extension Subscription {
    /// True while the stored lifecycle is still `.trial` - the form's
    /// trial-toggle prefill. Deliberately not `effectiveStatus`: a
    /// converted-unflipped trial still edits as the trial record it is, because
    /// the conversion is confirmed through the flow (which acknowledges the
    /// charge and appends the price change), never through an edit.
    public var editsAsTrial: Bool { storedStatus == .trial }

    /// The status an edit writes: the trial toggle decides between `.trial`
    /// and `.active`; every other lifecycle state is preserved untouched.
    public func editedStatus(isTrial: Bool) -> SubscriptionStatus {
        switch storedStatus {
        case .trial, .active:
            return isTrial ? .trial : .active
        case .paused, .cancellationPending, .cancelled, .archived:
            return storedStatus
        }
    }

    /// The trial an edit carries: the drafted term while the toggle is on; on
    /// a non-trial record the historical term untouched - a confirmed
    /// conversion keeps its term deliberately (§5.2a: confirming records,
    /// never deletes), and an unrelated edit must not silently delete it.
    /// Turning the toggle off on a still-trial record TOMBSTONES the term at
    /// `now`: that is the user saying "this was never a trial", and it must be
    /// said as an explicit deletion of the identified record - absence is not
    /// deletion (spec §4a), so a save could no longer express the removal.
    public func editedTrial(draft: TrialTerm?, droppedAt now: Date) -> TrialTerm? {
        if let draft { return draft }
        guard editsAsTrial, var dropped = trial else { return trial }
        dropped.deletedAt = now
        dropped.updatedAt = now
        return dropped
    }
}
