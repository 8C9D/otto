import Foundation

// MARK: - Lifecycle transitions (spec §5.1, §5.4)

// The intent-named writes that pair with §5.2a's read rule (v1.7): flows above
// layer 2 cannot touch the stored status, so every persisted transition is a
// domain decision with its guards and side-writes in one place. Each returns
// nil when there is nothing to do, which keeps the calling flows idempotent.
extension Subscription {
    /// Pauses billing (spec §5.1): the freeze point recorded (`pausedOn` - the
    /// day §7.2's paused-spend price freezes at), the resume date stored when
    /// the vendor gave one. Only a stored-active subscription pauses: the flow
    /// derives and persists a trial conversion FIRST (§5.2a's
    /// derive-before-you-mutate), and a still-paused one has nothing to re-pause.
    public func pausing(on today: CalendarDay, until resumesOn: CalendarDay?, at now: Date) -> Subscription? {
        guard storedStatus == .active else { return nil }
        var updated = self
        updated.storedStatus = .paused
        updated.pausedOn = today
        updated.pauseEndsOn = resumesOn
        updated.updatedAt = now
        return updated
    }

    /// Resumes billing: `.active`, both pause fields cleared. Also the manual
    /// path out of an indefinite pause - the frozen watermark then backfills
    /// the gap on the next scheduler pass (spec §5.3, v1.6). Accepts a
    /// derived-resumed pause too: persisting what the derivation already
    /// decided is an optimisation, never the mechanism (spec §5.2a).
    public func resuming(at now: Date) -> Subscription? {
        guard storedStatus == .paused else { return nil }
        var updated = self
        updated.storedStatus = .active
        updated.pauseEndsOn = nil
        updated.pausedOn = nil
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
    public func archiving(at now: Date) -> Subscription? {
        guard storedStatus != .archived else { return nil }
        var updated = self
        updated.storedStatus = .archived
        updated.updatedAt = now
        return updated
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
    /// Turning the toggle off on a still-trial record drops the term: that is
    /// the user saying "this was never a trial".
    public func editedTrial(draft: TrialTerm?) -> TrialTerm? {
        if let draft { return draft }
        return editsAsTrial ? nil : trial
    }
}
