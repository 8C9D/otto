import Foundation
import Testing
@testable import OttoDomain

// Spec §5.2a (v1.6): pause resume is derived, never awaited - the founding
// scenario's fourth escape route. A pause with a known end date is structurally
// identical to a trial with a known conversion date, and gets the same rule: a
// `.paused` subscription past `pauseEndsOn` IS `.active`, whether or not any
// flow ever wrote the resume through. An indefinite pause has no derivable
// resume date, expects nothing, and freezes the watermark instead (§5.3).

@Suite("Pause resume is derived (spec §5.2a, v1.6)")
struct PauseResumeDerivationTests {

    @Test("a pause past its end date is effectively active, unflipped or not")
    func derivedResume() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: try day(2026, 9, 1)
        )
        #expect(subscription.effectiveStatus(asOf: try day(2026, 8, 31)) == .paused)
        // The end date itself resumes: the vendor charges on the resume day.
        #expect(subscription.effectiveStatus(asOf: try day(2026, 9, 1)) == .active)
        #expect(subscription.effectiveStatus(asOf: try day(2026, 10, 15)) == .active)
        #expect(subscription.isResumedPause(asOf: try day(2026, 10, 15)))
    }

    @Test("an indefinite pause never resumes by derivation")
    func indefinitePauseStaysPaused() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: nil
        )
        #expect(subscription.effectiveStatus(asOf: try day(2027, 12, 31)) == .paused)
        #expect(!subscription.isResumedPause(asOf: try day(2027, 12, 31)))
    }

    @Test("a resumed subscription's closed episode never re-enters pause semantics")
    func closedEpisodeOnActive() throws {
        // v1.7 stored the pause as two fields, and a manual resume that left a
        // stale pauseEndsOn behind was a live hazard this test used to pin.
        // The episode shape (spec §5.3a) makes that state unconstructible -
        // resuming closes the episode inside the same value - so what remains
        // to pin is its replacement: a CLOSED episode is history, not the
        // current pause, and derives nothing.
        let subscription = try makeSubscription(
            status: .active, cycleStartDay: try day(2026, 6, 1),
            pauseEpisodes: [try makePauseEpisode(
                startedOn: try day(2026, 6, 15), scheduledResumeOn: try day(2026, 7, 1),
                endedOn: try day(2026, 7, 1), outcome: .resumed
            )]
        )
        #expect(subscription.currentPauseEpisode == nil)
        #expect(subscription.pauseEndsOn == nil)
        #expect(!subscription.isResumedPause(asOf: try day(2026, 8, 1)))
        #expect(subscription.effectiveStatus(asOf: try day(2026, 8, 1)) == .active)
    }
}

@Suite("Expected charges around a pause (spec §5.2a/§5.3, v1.6)")
struct PausedExpectedChargesTests {

    /// Monthly on the 1st, paused with pauseEndsOn Sep 1 2026 - the founding
    /// scenario's shape: the vendor resumes and charges Sep 1 and Oct 1.
    private func pausedFixture() throws -> Subscription {
        try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: try day(2026, 9, 1)
        )
    }

    @Test("a resumed pause expects the charges that fell after pauseEndsOn, however late the pass")
    func resumedPauseBackWindow() throws {
        let subscription = try pausedFixture()
        // The window reaches back to a watermark behind the pause end - the
        // app was closed the whole time. Both vendor charges are expected;
        // nothing from inside the pause is.
        let charges = expectedCharges(
            for: subscription,
            from: try day(2026, 7, 10),
            through: try day(2026, 10, 20),
            asOf: try day(2026, 10, 15)
        )
        #expect(charges.map(\.day) == [try day(2026, 9, 1), try day(2026, 10, 1)])
        #expect(charges.allSatisfy { $0.amountCents == 1099 })
    }

    @Test("a pass during the pause materializes the resumed sequence ahead of time")
    func duringPauseMaterializesResumedSequence() throws {
        let subscription = try pausedFixture()
        // As of Aug 15 the subscription is still effectively paused, but the
        // resumed sequence is already certain - its rows are what make the
        // watermark safe to advance while paused (spec §5.3, v1.6).
        let charges = expectedCharges(
            for: subscription,
            from: try day(2026, 8, 15),
            through: try day(2026, 11, 20),
            asOf: try day(2026, 8, 15)
        )
        #expect(charges.map(\.day) == [
            try day(2026, 9, 1), try day(2026, 10, 1), try day(2026, 11, 1)
        ])
    }

    @Test("an indefinite pause expects nothing")
    func indefinitePauseExpectsNothing() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: nil
        )
        let charges = expectedCharges(
            for: subscription,
            from: try day(2026, 6, 1),
            through: try day(2026, 12, 31),
            asOf: try day(2026, 10, 15)
        )
        #expect(charges.isEmpty)
    }

    @Test("membership matches materialization on both sides of the pause end")
    func membershipMirrorsMaterialization() throws {
        let subscription = try pausedFixture()
        let duringPause = try day(2026, 8, 1)
        let afterResume = try day(2026, 9, 1)
        // Still paused today: rows inside the pause are phantoms, resumed rows valid.
        #expect(!isExpectedCharge(
            day: duringPause, amountCents: 1099, for: subscription, asOf: try day(2026, 8, 15)
        ))
        #expect(isExpectedCharge(
            day: afterResume, amountCents: 1099, for: subscription, asOf: try day(2026, 8, 15)
        ))
        // Derived-resumed today: same answers.
        #expect(!isExpectedCharge(
            day: duringPause, amountCents: 1099, for: subscription, asOf: try day(2026, 10, 15)
        ))
        #expect(isExpectedCharge(
            day: afterResume, amountCents: 1099, for: subscription, asOf: try day(2026, 10, 15)
        ))
    }
}

@Suite("Consumers act on the derived resume")
struct PauseResumeConsumerTests {

    @Test("Today classifies a resumed pause as an upcoming charge, not a resume")
    func todayEntryAfterResume() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: try day(2026, 9, 1)
        )
        let entry = try #require(todayEntry(
            for: subscription, cancellation: nil, from: try day(2026, 10, 15)
        ))
        #expect(entry.reason == .upcomingCharge(amountCents: 1099))
        #expect(entry.date == (try day(2026, 11, 1)))
    }

    @Test("the planner plans renewals for a resumed pause")
    func remindersAfterResume() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: try day(2026, 9, 1)
        )
        let plan = reminderSchedule(
            for: subscription, from: try day(2026, 10, 15), horizonDays: 90
        )
        #expect(plan.contains {
            $0.kind == .renewal && $0.day == (try? day(2026, 10, 29))
        })
        #expect(!plan.contains { $0.kind == .pauseEnding })
    }
}
