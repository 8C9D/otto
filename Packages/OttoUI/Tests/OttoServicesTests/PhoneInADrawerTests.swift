import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// The founding scenario as a STANDING HARNESS (spec §5.3, v1.5). The
// phone-in-a-drawer case has now escaped through three distinct mechanisms
// across three waves - status derivation (§5.2a), the check-date ordering bug
// (Wave 4), and the forward-only materialization window (v1.4 §5.3) - so it is
// a harness every subsystem runs against, not a test someone remembers to
// write. Every test here uses the same shape: seed a world, let NOTHING execute
// for the gap, run the first scheduler pass on wake day, and assert the
// subsystem's state is what timely daily passes would have produced.
//
// A NEW subsystem with any time-dependent behavior gets a test in this file as
// part of landing it. Do not assume it inherits the property - none of the
// three escapes above did.

@Suite("Phone in a drawer: the app never opens for the gap (spec §5.3, v1.5)")
struct PhoneInADrawerTests {

    /// The shared drawer run: the FIRST scheduler pass, on wake day - nothing
    /// has executed since the world was seeded, which is the point.
    private func wake(
        _ fixture: SchedulerFixture, on wakeDay: CalendarDay
    ) async throws -> ScheduleOutcome {
        var components = DateComponents()
        components.year = wakeDay.year
        components.month = wakeDay.month
        components.day = wakeDay.day
        components.hour = 8
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = torontoZone
        let now = try #require(gregorian.date(from: components))
        return try await fixture.scheduler.reschedule(now: now, today: wakeDay, timeZone: torontoZone)
    }

    private struct TrialWorld {
        let fixture: SchedulerFixture
        let subscription: Subscription
        let trial: TrialTerm
    }

    /// A trial entered Aug 1, converting Aug 15, drawer until Sep 20.
    private func convertedTrialWorld() async throws -> TrialWorld {
        let fixture = SchedulerFixture()
        let trial = try makeTrialTerm(
            startDate: try day(2026, 8, 1), lengthDays: 14, convertsToAmountCents: 1599
        )
        let subscription = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 8, 1),
            lastMaterializedThrough: try day(2026, 8, 1), trial: trial
        )
        await fixture.subscriptions.seed([subscription])
        return TrialWorld(fixture: fixture, subscription: subscription, trial: trial)
    }

    @Test("status derivation: the trial that converted in the drawer IS active on wake, unflipped or not")
    func statusDerivation() async throws {
        let world = try await convertedTrialWorld()
        let (fixture, subscription, trial) = (world.fixture, world.subscription, world.trial)
        let wakeDay = try day(2026, 9, 20)
        _ = try await wake(fixture, on: wakeDay)

        // The stored status still says .trial - no flow ran to flip it - and
        // every consumer must already treat it as active at the converted price.
        let stored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(stored.storedStatus == .trial)
        #expect(stored.effectiveStatus(asOf: wakeDay) == .active)
        #expect(stored.billingAmountCents(asOf: wakeDay) == trial.convertsToAmountCents)
        // And no trial-deadline reminder survives for a deadline that is history.
        let kinds = await fixture.client.pendingRequests()
            .compactMap { NotificationPlanIdentifier.kind(of: $0.identifier) }
        #expect(!kinds.contains(.trialLead))
        #expect(!kinds.contains(.trialDayOfMorning))
    }

    @Test("materialization: the conversion charge that fell in the drawer has its ledger row on wake")
    func materialization() async throws {
        let world = try await convertedTrialWorld()
        let (fixture, subscription, trial) = (world.fixture, world.subscription, world.trial)
        let outcome = try await wake(fixture, on: try day(2026, 9, 20))
        #expect(outcome.ledgerFailures.isEmpty)

        // The row exists at the conversion date and converted amount - plus the
        // paid cycle that ALSO passed in the drawer (Sep 15). This is the v1.5
        // watermark reaching backwards; v1.4 materialized neither.
        let rows = try await fixture.billingEvents.events(forSubscription: subscription.id)
        let paidCycleInDrawer = try day(2026, 9, 15)
        #expect(rows.contains { $0.expectedDate == trial.conversionDate
            && $0.expectedAmountCents == trial.convertsToAmountCents })
        #expect(rows.contains { $0.expectedDate == paidCycleInDrawer })
    }

    @Test("reminder planning: wake plans only forward - future fire dates, next charges, no debris")
    func reminderPlanning() async throws {
        let fixture = SchedulerFixture()
        // A plain subscription billing the 15th, seeded in August, drawer until
        // Dec 20: four charge dates pass unreminded and unmaterialized.
        let subscription = try makeSubscription(
            index: 1, cycleStartDay: try day(2026, 1, 15),
            lastMaterializedThrough: try day(2026, 8, 6)
        )
        await fixture.subscriptions.seed([subscription])
        let wakeDay = try day(2026, 12, 20)
        _ = try await wake(fixture, on: wakeDay)

        let requests = await fixture.client.pendingRequests()
        #expect(!requests.isEmpty)
        // Nothing dated behind wake day: a calendar trigger in the past would
        // never fire, and planning one would claim coverage that cannot happen.
        for request in requests {
            let requestDay = try #require(
                CalendarDay(year: request.year, month: request.month, day: request.day)
            )
            #expect(requestDay >= wakeDay)
        }
        // And the next real charge (Jan 15) is covered by a renewal reminder.
        let kinds = requests.compactMap { NotificationPlanIdentifier.kind(of: $0.identifier) }
        #expect(kinds.contains(.renewal))
    }

    @Test("pause resume: a pause that ended in the drawer is active on wake, with both vendor charges materialized")
    func pauseResumeDerivation() async throws {
        let fixture = SchedulerFixture()
        // Paused in August until Sep 1, monthly on the 1st; the drawer lasts
        // until Oct 15. The vendor resumed on schedule and charged Sep 1 and
        // Oct 1. Before spec v1.6 the watermark advanced through the pause, so
        // a manual resume could never backfill those two charges - the fourth
        // escape route.
        let subscription = try makeSubscription(
            index: 1, status: .paused, cycleStartDay: try day(2026, 6, 1),
            pauseEndsOn: try day(2026, 9, 1),
            lastMaterializedThrough: try day(2026, 8, 20)
        )
        await fixture.subscriptions.seed([subscription])
        let wakeDay = try day(2026, 10, 15)
        _ = try await wake(fixture, on: wakeDay)

        // The stored status still says .paused - no flow ran to flip it - and
        // every consumer must already treat it as active.
        let stored = try #require(try await fixture.subscriptions.subscription(withID: subscription.id))
        #expect(stored.storedStatus == .paused)
        #expect(stored.effectiveStatus(asOf: wakeDay) == .active)

        // Both charges that fell in the drawer have ledger rows; nothing from
        // inside the pause does.
        let rows = try await fixture.billingEvents.events(forSubscription: subscription.id)
        let resumeDay = try day(2026, 9, 1)
        #expect(rows.contains { $0.expectedDate == resumeDay })
        #expect(rows.contains { $0.expectedDate == (try? day(2026, 10, 1)) })
        #expect(rows.allSatisfy { $0.expectedDate >= resumeDay })

        // And the next charge plans a renewal reminder, not a pause-ending one.
        let kinds = await fixture.client.pendingRequests()
            .compactMap { NotificationPlanIdentifier.kind(of: $0.identifier) }
        #expect(kinds.contains(.renewal))
        #expect(!kinds.contains(.pauseEnding))
    }

    @Test("verification roll-forward: three checks missed in the drawer escalate on wake, exactly once")
    func verificationRollForward() async throws {
        let fixture = SchedulerFixture()
        let subscription = try makeSubscription(
            index: 1, status: .cancelled, cycleStartDay: try day(2026, 1, 15)
        )
        await fixture.subscriptions.seed([subscription])
        await fixture.cancellations.seed([CancellationRecord(
            id: try fixtureUUID(600),
            subscriptionID: subscription.id,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )])

        // Aug 15, Sep 15, Oct 15 (and Nov 15) all pass unanswered in the drawer.
        _ = try await wake(fixture, on: try day(2026, 12, 20))

        // One wake resolves to the same state three timely passes would have:
        // escalated at exactly the three-check limit, generating no further
        // verification notifications.
        let record = try #require(try await fixture.cancellations.record(forSubscription: subscription.id))
        #expect(record.verificationState == .needsManualReview)
        #expect(record.unansweredCheckCount == unansweredCheckLimit)
        let kinds = await fixture.client.pendingRequests()
            .compactMap { NotificationPlanIdentifier.kind(of: $0.identifier) }
        #expect(!kinds.contains(.verification))
    }
}
