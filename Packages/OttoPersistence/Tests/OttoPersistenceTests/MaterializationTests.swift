import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

extension SerializedPersistenceTests {
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

        @Test("a soft-deleted history row is never resurrected by re-materialization")
        func tombstoneNotResurrected() async throws {
            let (store, container) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)
            let today = try day(2026, 8, 6)
            _ = try await store.materializeEvents(
                for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            // A resolved row deliberately removed from history. (A tombstoned .upcoming
            // row behaves differently by design: it is a §5.3 invalidation artifact and
            // does not block its date - see the schedule-change invalidation suite.)
            let context = ModelContext(container)
            let events = try context.fetch(FetchDescriptor<StoredBillingEvent>())
            let target = try #require(events.first { $0.expectedDate == 20260930 })
            target.state = BillingEvent.State.skipped.rawValue
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

        @Test("a converted trial materializes the paid sequence from its conversion anchor (spec §5.2a)")
        func convertedTrialMaterializesPaidSequence() async throws {
            let (store, _) = try makeStore()
            // Converted Aug 13 to $11.00 monthly; today is Sep 1 and no flow ever
            // persisted a status flip - the status still says .trial.
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7, convertsToAmountCents: 1100)
            let subscription = try makeSubscription(status: .trial, cycleStartDay: try day(2026, 8, 6), trial: trial)
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 9, 1), horizonDays: 90, maxReminderLeadDays: 5, at: instant
            )

            // Window runs through Dec 5: the paid charges land Sep 13, Oct 13, Nov 13,
            // each at the converted amount.
            #expect(created.map(\.expectedDate) == [try day(2026, 9, 13), try day(2026, 10, 13), try day(2026, 11, 13)])
            #expect(created.allSatisfy { $0.expectedAmountCents == 1100 })
            #expect(created.allSatisfy { $0.state == .upcoming })
        }

        @Test("cancellation and archived statuses materialize nothing", arguments: [
            SubscriptionStatus.cancellationPending, .cancelled, .archived
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
}

// Spec §5.3 (v1.5): the window reaches back to the lastMaterializedThrough
// watermark, so no charge date can pass unobserved between scheduler runs -
// however long the phone sits in a drawer.
extension SerializedPersistenceTests {
    @Suite("The materialization watermark (spec §5.3, v1.5)")
    struct MaterializationWatermarkTests {

        private let instant = Date(timeIntervalSince1970: 8_000)

        @Test("the founding scenario at the ledger layer: a conversion behind today on the FIRST pass still gets its row")
        func foundingScenarioConversionBehindToday() async throws {
            let (store, _) = try makeStore()
            // Trial entered Aug 1 (watermark = entry day), converting Aug 15 for
            // 1599. The phone then sits in a drawer; the first scheduler pass EVER
            // runs Sep 20 - the conversion date is 36 days behind today, and v1.4
            // materialized from today forward, so the single most important charge
            // in the product got no row, no verification, no mismatch coverage.
            let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
            let subscription = try makeSubscription(
                status: .trial,
                cycleStartDay: try day(2026, 8, 1),
                lastMaterializedThrough: try day(2026, 8, 1),
                trial: trial
            )
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 9, 20), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            // The conversion row exists, at the converted amount, plus the paid
            // cycles the window reaches: Sep 15 (also behind today) and Oct 15.
            #expect(created.map(\.expectedDate) == [try day(2026, 8, 15), try day(2026, 9, 15), try day(2026, 10, 15)])
            #expect(created.allSatisfy { $0.expectedAmountCents == trial.convertsToAmountCents })
            #expect(created.allSatisfy { $0.state == .upcoming })
        }

        @Test("a gap between passes loses nothing: the second pass reaches back to the first pass's watermark")
        func gapBetweenPassesIsCovered() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)

            // Pass 1 on Aug 6 covers through Nov 4 (Aug 31, Sep 30, Oct 31). The app
            // then goes unopened until Dec 20 - Nov 30's charge date falls entirely
            // between the passes, which is exactly the hole v1.4's from-today window
            // left open.
            _ = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            #expect(reloaded.lastMaterializedThrough == (try day(2026, 11, 4)))

            let second = try await store.materializeEvents(
                for: reloaded, from: try day(2026, 12, 20), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            #expect(second.map(\.expectedDate).contains(try day(2026, 11, 30)))
            #expect(second.map(\.expectedDate).contains(try day(2026, 12, 31)))
        }

        @Test("the stored watermark governs, not the caller's snapshot - a stale domain value cannot reopen the window")
        func storedWatermarkGoverns() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)
            _ = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            // The caller re-runs with its ORIGINAL snapshot (watermark still nil):
            // the stored watermark - not the stale value - decides the window, and
            // dedup keeps the result empty either way.
            let rerun = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            #expect(rerun == [])
        }

        @Test("a pre-v1.5 record (nil watermark) materializes from today once and carries a watermark thereafter")
        func nilWatermarkStartsAtToday() async throws {
            let (store, _) = try makeStore()
            // Anchor months behind today, no watermark: the pass must NOT backfill
            // Feb-Jul rows the record never had - it starts at today, the v1.4
            // behavior, exactly once.
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            #expect(created.map(\.expectedDate) == [try day(2026, 8, 31)])
            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            #expect(reloaded.lastMaterializedThrough == (try day(2026, 9, 5)))
        }

        @Test("an empty pass still advances the watermark: observing nothing is an observation")
        func emptyPassAdvancesWatermark() async throws {
            let (store, _) = try makeStore()
            // An active subscription whose first charge is beyond the window: the
            // pass creates nothing, but it observed the window and records that.
            let subscription = try makeSubscription(
                cycleStartDay: try day(2027, 3, 1),
                lastMaterializedThrough: try day(2026, 8, 1)
            )
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            #expect(created == [])
            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            #expect(reloaded.lastMaterializedThrough == (try day(2026, 9, 5)))
        }

        @Test("watermark writes never bump updatedAt - bookkeeping is not a user edit (spec §5.3, v1.6)")
        func watermarkWriteLeavesUpdatedAtAlone() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)

            _ = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            #expect(reloaded.lastMaterializedThrough == (try day(2026, 11, 4)))
            #expect(reloaded.updatedAt == subscription.updatedAt)
        }
    }
}
