import Foundation
import Testing
@testable import OttoDomain

// The intent-named transitions that pair with §5.2a's v1.7 read rule: with the
// stored status unreadable above layer 2, these are the only persisted writes,
// so their guards and side-writes are pinned here once for every calling flow.
@Suite("Lifecycle transitions (spec §5.1, §5.4, v1.7)")
struct LifecycleTransitionTests {

    private let now = Date(timeIntervalSince1970: 5_000)

    @Test("pausing records the freeze point and the resume date, and only from stored-active")
    func pausing() throws {
        let active = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))

        let paused = try #require(
            active.pausing(on: try day(2026, 8, 7), until: try day(2026, 12, 1), at: now)
        )
        #expect(paused.storedStatus == .paused)
        #expect(paused.pausedOn == (try day(2026, 8, 7)))
        #expect(paused.pauseEndsOn == (try day(2026, 12, 1)))
        #expect(paused.updatedAt == now)

        // Nothing to re-pause, nothing to pause on a trial or a cancellation:
        // the flow converts a trial first and never pauses a watched record.
        #expect(paused.pausing(on: try day(2026, 8, 8), until: nil, at: now) == nil)
        let trial = try makeSubscription(
            status: .trial,
            cycleStartDay: try day(2026, 8, 1),
            trial: try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 30)
        )
        #expect(trial.pausing(on: try day(2026, 8, 7), until: nil, at: now) == nil)
    }

    @Test("resuming clears both pause fields and only applies to a stored pause")
    func resuming() throws {
        let active = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))
        let paused = try #require(
            active.pausing(on: try day(2026, 8, 7), until: try day(2026, 12, 1), at: now)
        )

        let resumed = try #require(paused.resuming(at: now))
        #expect(resumed.storedStatus == .active)
        #expect(resumed.pauseEndsOn == nil)
        #expect(resumed.pausedOn == nil)
        #expect(resumed.updatedAt == now)

        #expect(active.resuming(at: now) == nil)
    }

    @Test("marking cancellation-pending never regresses a lifecycle at or past cancellation")
    func markingCancellationPending() throws {
        let active = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))
        let pending = try #require(active.markingCancellationPending(at: now))
        #expect(pending.storedStatus == .cancellationPending)
        #expect(pending.updatedAt == now)

        #expect(pending.markingCancellationPending(at: now) == nil)
        let archived = try makeSubscription(status: .archived, cycleStartDay: try day(2026, 1, 15))
        #expect(archived.markingCancellationPending(at: now) == nil)
    }

    @Test("archiving is idempotent - the lifecycle's actual end")
    func archiving() throws {
        let pending = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let archived = try #require(pending.archiving(at: now))
        #expect(archived.storedStatus == .archived)
        #expect(archived.archiving(at: now) == nil)
    }
}

// The two places an edit legitimately depends on the stored lifecycle, kept in
// the domain so the form never reads it (spec §7.1; §5.2a v1.7).
@Suite("Record-preserving edits (spec §7.1)")
struct RecordPreservingEditTests {

    @Test("the trial toggle decides between trial and active; every other state is preserved")
    func editedStatus() throws {
        let trial = try makeSubscription(
            status: .trial,
            cycleStartDay: try day(2026, 8, 1),
            trial: try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 30)
        )
        #expect(trial.editedStatus(isTrial: true) == .trial)
        #expect(trial.editedStatus(isTrial: false) == .active)

        let active = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))
        #expect(active.editedStatus(isTrial: true) == .trial)

        let paused = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: try day(2026, 12, 1)
        )
        #expect(paused.editedStatus(isTrial: false) == .paused)
        let archived = try makeSubscription(status: .archived, cycleStartDay: try day(2026, 1, 15))
        #expect(archived.editedStatus(isTrial: true) == .archived)
    }

    @Test("a confirmed conversion's term survives an unrelated edit; unmarking a live trial drops it")
    func editedTrial() throws {
        let term = try makeTrialTerm(startDate: try day(2026, 6, 1), lengthDays: 30)
        let converted = try makeSubscription(
            status: .active, cycleStartDay: try day(2026, 7, 1), trial: term
        )
        #expect(converted.editedTrial(draft: nil) == term)

        let stillTrial = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 6, 1), trial: term
        )
        #expect(stillTrial.editedTrial(draft: nil) == nil)

        let redrafted = try makeTrialTerm(index: 501, startDate: try day(2026, 6, 2), lengthDays: 14)
        #expect(stillTrial.editedTrial(draft: redrafted) == redrafted)
    }
}
