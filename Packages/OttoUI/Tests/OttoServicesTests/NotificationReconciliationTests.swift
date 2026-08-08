import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// Wave 10, defects B and C: the reschedule pass reconciles the desired plan
// against the device instead of remove-all-then-re-add. The old shape held a
// window in which a suspension left the device with NOTHING pending - observed
// on a physical device at 5 ms from losing every trial rung - and a
// conversion-day reschedule after 09:00 permanently cancelled the announcement.
// These tests assert on the device state AT the suspension point, not on the
// final state, because the window IS the defect.

@Suite("Reschedule reconciliation (Wave 10, defects B and C)")
struct NotificationReconciliationTests {

    /// Trial entered Aug 6: 14 days, 2-day buffer - cancel-by Aug 18,
    /// conversion Aug 20. Ladder: lead Aug 15, morning+evening Aug 18, daily
    /// Aug 19, announcement Aug 20.
    private func trialWorld() async throws -> (fixture: SchedulerFixture, subscription: Subscription) {
        let fixture = SchedulerFixture()
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 14, bufferDays: 2)
        let subscription = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 8, 6), trial: trial
        )
        await fixture.subscriptions.seed([subscription])
        return (fixture, subscription)
    }

    private func at(
        _ target: CalendarDay, hour: Int, minute: Int = 0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = torontoZone
        return try #require(gregorian.date(from: DateComponents(
            year: target.year, month: target.month, day: target.day, hour: hour, minute: minute
        )), sourceLocation: sourceLocation)
    }

    private func pendingKinds(_ fixture: SchedulerFixture) async -> [PlannedReminder.Kind] {
        await fixture.client.pendingRequests()
            .compactMap { NotificationPlanIdentifier.kind(of: $0.identifier) }
    }

    @Test("a reschedule against a matching device state issues ZERO removes")
    func matchingStateRemovesNothing() async throws {
        let (fixture, _) = try await trialWorld()
        let today = try day(2026, 8, 6)
        let now = try at(today, hour: 8)
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        await fixture.client.clearCallLog()

        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        #expect(await fixture.client.removeCalls.isEmpty)
    }

    @Test("a second identical run is a complete no-op: no removes, no adds, byte-identical pending set")
    func secondRunIsNoOp() async throws {
        let (fixture, _) = try await trialWorld()
        let today = try day(2026, 8, 6)
        let now = try at(today, hour: 8)
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let first = await fixture.client.pendingRequests()
        await fixture.client.clearCallLog()

        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        #expect(await fixture.client.removeCalls.isEmpty)
        #expect(await fixture.client.addCalls.isEmpty)
        #expect(await fixture.client.pendingRequests() == first)
        #expect(!first.isEmpty)
    }

    @Test("⛔ suspension after the removes, before any add: every rung that should exist still exists")
    func suspensionLeavesCorrectSet() async throws {
        // Day 1: the full ladder lands. Day 11 (Aug 16): the lead rung is
        // stale, a freshly added second subscription needs new requests - and
        // the app is suspended before a single add can land.
        let (fixture, _) = try await trialWorld()
        let seeded = try day(2026, 8, 6)
        _ = try await fixture.scheduler.reschedule(
            now: try at(seeded, hour: 8), today: seeded, timeZone: torontoZone
        )
        await fixture.subscriptions.seed([
            try makeSubscription(index: 2, cycleStartDay: try day(2026, 8, 25))
        ])
        let wakeDay = try day(2026, 8, 16)
        await fixture.client.refuseAdds(after: 0)

        await #expect(throws: FakeNotificationClient.AddRefused.self) {
            _ = try await fixture.scheduler.reschedule(
                now: try at(wakeDay, hour: 8), today: wakeDay, timeZone: torontoZone
            )
        }

        // The device state AT the suspension point: the four rungs still ahead
        // - morning, evening, daily, announcement - are all pending. Under
        // remove-all-then-re-add this set is EMPTY, silently, and the phone
        // sits in the drawer with no ladder at all.
        let kinds = await pendingKinds(fixture)
        #expect(kinds.contains(.trialDayOfMorning))
        #expect(kinds.contains(.trialDayOfEvening))
        #expect(kinds.contains(.trialDaily))
        #expect(kinds.contains(.conversionAnnouncement))
    }

    @Test("a changed spec is replaced by add-over-the-top, never removed first")
    func changedContentReplacesInPlace() async throws {
        let fixture = SchedulerFixture()
        var subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 8, 25))
        await fixture.subscriptions.seed([subscription])
        let today = try day(2026, 8, 20)
        let now = try at(today, hour: 8)
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)
        let before = await fixture.client.pendingRequests()
        #expect(!before.isEmpty)

        // A price edit changes every pending renewal body under the SAME
        // identifiers: each is one add-over-the-top, nothing is removed.
        subscription.amountCents = 1599
        await fixture.subscriptions.seed([subscription])
        await fixture.client.clearCallLog()
        _ = try await fixture.scheduler.reschedule(now: now, today: today, timeZone: torontoZone)

        #expect(await fixture.client.removeCalls.isEmpty)
        #expect(await fixture.client.addCalls.map(\.identifier) == before.map(\.identifier))
        let replaced = await fixture.client.pendingRequests()
        #expect(replaced.map(\.identifier) == before.map(\.identifier))
        #expect(replaced.allSatisfy { $0.body.contains("$15.99") })
    }

    @Test("⛔ a reschedule at 09:01 on conversion day: the announcement survives")
    func announcementSurvivesConversionMorningReschedule() async throws {
        let (fixture, _) = try await trialWorld()
        let cancelBy = try day(2026, 8, 18)
        _ = try await fixture.scheduler.reschedule(
            now: try at(cancelBy, hour: 8), today: cancelBy, timeZone: torontoZone
        )
        #expect(await pendingKinds(fixture).contains(.conversionAnnouncement))

        // 09:01 on conversion day: the passed-hour filter drops the
        // announcement from the desired plan, which under remove-all-then-add
        // permanently cancelled the one notification that says money started
        // moving. Reconciliation is structurally unable to remove it.
        let conversionDay = try day(2026, 8, 20)
        _ = try await fixture.scheduler.reschedule(
            now: try at(conversionDay, hour: 9, minute: 1), today: conversionDay, timeZone: torontoZone
        )

        #expect(await pendingKinds(fixture).contains(.conversionAnnouncement))
    }

    @Test("⛔ after 'Keeping it', the 09:01 reschedule drops the escalation and keeps the announcement")
    func keepingItWaivesEscalationNeverAnnouncement() async throws {
        let (fixture, subscription) = try await trialWorld()
        let cancelBy = try day(2026, 8, 18)
        _ = try await fixture.scheduler.reschedule(
            now: try at(cancelBy, hour: 8), today: cancelBy, timeZone: torontoZone
        )
        // "Keeping it" acknowledges the conversion charge (§6.4); the ladder's
        // remaining requests are waived, the announcement is not a request.
        try await fixture.flows.acknowledgeCurrentCharge(
            subscriptionID: subscription.id, now: try at(cancelBy, hour: 8, minute: 5), today: cancelBy
        )

        let conversionDay = try day(2026, 8, 20)
        _ = try await fixture.scheduler.reschedule(
            now: try at(conversionDay, hour: 9, minute: 1), today: conversionDay, timeZone: torontoZone
        )

        let kinds = await pendingKinds(fixture)
        #expect(!kinds.contains(.trialDayOfMorning))
        #expect(!kinds.contains(.trialDayOfEvening))
        #expect(!kinds.contains(.trialDaily))
        #expect(kinds.contains(.conversionAnnouncement))
    }

    @Test("a reschedule at 23:59 on conversion day: the announcement is still pending")
    func announcementSurvivesLateNightReschedule() async throws {
        // Prediction, stated before running: 23:59 behaves exactly like 09:01,
        // because the protection keys on the announcement's DATE being today,
        // not on how far past the fire hour the reschedule runs. The pending
        // announcement survives.
        let (fixture, _) = try await trialWorld()
        let cancelBy = try day(2026, 8, 18)
        _ = try await fixture.scheduler.reschedule(
            now: try at(cancelBy, hour: 8), today: cancelBy, timeZone: torontoZone
        )

        let conversionDay = try day(2026, 8, 20)
        _ = try await fixture.scheduler.reschedule(
            now: try at(conversionDay, hour: 23, minute: 59), today: conversionDay, timeZone: torontoZone
        )

        #expect(await pendingKinds(fixture).contains(.conversionAnnouncement))
    }

    @Test("a stale past-dated announcement IS removable - only its own day is protected")
    func pastAnnouncementIsRemovable() async throws {
        let (fixture, _) = try await trialWorld()
        let cancelBy = try day(2026, 8, 18)
        _ = try await fixture.scheduler.reschedule(
            now: try at(cancelBy, hour: 8), today: cancelBy, timeZone: torontoZone
        )

        // The day AFTER conversion, the never-delivered announcement claims
        // "converted today" about yesterday - the dishonesty v1.4 legislated
        // against. It goes.
        let dayAfter = try day(2026, 8, 21)
        _ = try await fixture.scheduler.reschedule(
            now: try at(dayAfter, hour: 8), today: dayAfter, timeZone: torontoZone
        )

        #expect(await !pendingKinds(fixture).contains(.conversionAnnouncement))
    }

    @Test("cancelling a trial before conversion removes the future announcement - nothing converts")
    func cancelledTrialAnnouncementIsRemovable() async throws {
        let (fixture, subscription) = try await trialWorld()
        let entry = try day(2026, 8, 10)
        _ = try await fixture.scheduler.reschedule(
            now: try at(entry, hour: 8), today: entry, timeZone: torontoZone
        )
        #expect(await pendingKinds(fixture).contains(.conversionAnnouncement))

        // Cancelled Aug 12, well before the Aug 20 conversion: no money will
        // move on Aug 20, so the future-dated announcement must go - the
        // protection covers only an announcement on its own conversion day.
        let cancelDay = try day(2026, 8, 12)
        _ = try await fixture.flows.startCancellation(
            subscriptionID: subscription.id, now: try at(cancelDay, hour: 10), today: cancelDay
        )
        _ = try await fixture.scheduler.reschedule(
            now: try at(cancelDay, hour: 10, minute: 1), today: cancelDay, timeZone: torontoZone
        )

        #expect(await !pendingKinds(fixture).contains(.conversionAnnouncement))
    }
}
