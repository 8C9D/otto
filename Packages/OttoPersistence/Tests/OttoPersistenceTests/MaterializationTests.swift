import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

@Suite("BillingEvent materialization (spec §5.3)")
struct MaterializationTests {

    /// The audit instant every materialization in this suite stamps rows with.
    private let instant = Date(timeIntervalSince1970: 8_000)

    @Test("rows are created for every billing date inside the window and none beyond it")
    func horizonCoverage() async throws {
        let (store, _) = try makeStore()
        // Jan 31 monthly exercises the clamp: inside [Aug 6, Nov 4] the charges are
        // Aug 31, Sep 30, Oct 31.
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: instant
        )

        let expectedDates = [try day(2026, 8, 31), try day(2026, 9, 30), try day(2026, 10, 31)]
        #expect(created.map(\.expectedDate) == expectedDates)
        #expect(created.allSatisfy { $0.state == .upcoming })
        #expect(created.allSatisfy { $0.expectedAmountCents == subscription.amountCents })
        #expect(created.allSatisfy { $0.subscriptionID == subscription.id })
        #expect(created.allSatisfy { $0.createdAt == instant && $0.updatedAt == instant && $0.deletedAt == nil })

        let persisted = try await store.events(forSubscription: subscription.id)
        #expect(persisted.map(\.expectedDate) == expectedDates)
    }

    @Test("a charge landing today is materialized - today is inside the window")
    func includesToday() async throws {
        let (store, _) = try makeStore()
        let today = try day(2026, 8, 6)
        let subscription = try makeSubscription(cycleStartDay: today)
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
        )

        #expect(created.first?.expectedDate == today)
    }

    @Test("the reminder window governs: the lead days widen the charge window beyond the horizon")
    func reminderWindowGoverns() async throws {
        let (store, _) = try makeStore()
        // First charge lands Sep 10 - past the 30-day horizon end (Sep 5), but
        // inside it once the 7-day reminder lead is added (Sep 12). The reminder for
        // that charge falls inside the horizon, so its row must exist (spec §5.3).
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 9, 10))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)

        let withoutLead = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 30, maxReminderLeadDays: 0, at: instant
        )
        let withLead = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 30, maxReminderLeadDays: 7, at: instant
        )

        #expect(withoutLead == [])
        #expect(withLead.map(\.expectedDate) == [try day(2026, 9, 10)])
    }

    @Test("re-running is idempotent and creates no duplicates")
    func idempotent() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)

        let first = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )
        let second = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )

        #expect(first.count == 3)
        #expect(second == [])
        #expect(try await store.events(forSubscription: subscription.id).count == 3)
    }

    @Test("a longer horizon on a later run creates only the missing rows")
    func extendingHorizon() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)

        let first = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 30, maxReminderLeadDays: 0, at: instant
        )
        let second = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
        )

        #expect(first.map(\.expectedDate) == [try day(2026, 8, 31)])
        #expect(second.map(\.expectedDate) == [try day(2026, 9, 30), try day(2026, 10, 31)])
    }

    @Test("a soft-deleted row is never resurrected by re-materialization")
    func tombstoneNotResurrected() async throws {
        let (store, container) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)
        let today = try day(2026, 8, 6)
        _ = try await store.materializeEvents(
            for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
        )

        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<StoredBillingEvent>())
        let target = try #require(events.first { $0.expectedDate == 20260930 })
        target.deletedAt = Date(timeIntervalSince1970: 9_000)
        try context.save()

        let fresh = OttoStore(modelContainer: container)
        let created = try await fresh.materializeEvents(
            for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
        )

        #expect(created == [])
        #expect(try await fresh.events(forSubscription: subscription.id).count == 2)
    }

    @Test("a trial materializes exactly one event: the conversion charge, at the converted amount")
    func trialMaterializesConversion() async throws {
        let (store, _) = try makeStore()
        // Trial starts Aug 1, runs 14 days: conversion Aug 15, for 1599 cents - not
        // the subscription's 1099. This is the charge the app exists to catch; it
        // gets a ledger row like any other expected charge (spec §5.3, v1.2).
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial)
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )

        #expect(created.count == 1)
        #expect(created.first?.expectedDate == trial.conversionDate)
        #expect(created.first?.expectedAmountCents == trial.convertsToAmountCents)
        #expect(created.first?.state == .upcoming)

        let rerun = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )
        #expect(rerun == [])
        #expect(try await store.events(forSubscription: subscription.id).count == 1)
    }

    @Test("a trial converting beyond the window materializes nothing yet")
    func trialConversionBeyondWindow() async throws {
        let (store, _) = try makeStore()
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 60)
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial)
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 20, maxReminderLeadDays: 5, at: instant
        )

        #expect(created == [])
    }

    @Test("a trial whose conversion date has already passed materializes nothing - the window starts today")
    func trialConversionInThePast() async throws {
        let (store, _) = try makeStore()
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 14)
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial)
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 9, 1), horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )

        #expect(created == [])
    }

    @Test("a trial-status subscription with no trial term materializes nothing")
    func trialWithoutTerm() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 1))
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )

        #expect(created == [])
    }

    @Test("paused, cancellation, and archived statuses materialize nothing", arguments: [
        SubscriptionStatus.paused, .cancellationPending, .cancelled, .archived
    ])
    func nonExpectingStatusesMaterializeNothing(status: SubscriptionStatus) async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(status: status, cycleStartDay: try day(2026, 1, 31))
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )

        #expect(created == [])
        #expect(try await store.events(forSubscription: subscription.id) == [])
    }

    @Test("materializing for an unsaved subscription is an explicit error")
    func unsavedSubscription() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))

        await #expect(throws: RepositoryError.subscriptionNotFound(subscription.id)) {
            _ = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: self.instant
            )
        }
    }

    @Test("an anchor beyond the window produces nothing - rows past the window do not exist")
    func anchorBeyondHorizon() async throws {
        let (store, _) = try makeStore()
        let subscription = try makeSubscription(cycleStartDay: try day(2027, 3, 1))
        try await store.save(subscription)

        let created = try await store.materializeEvents(
            for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 5, at: instant
        )

        #expect(created == [])
    }
}
