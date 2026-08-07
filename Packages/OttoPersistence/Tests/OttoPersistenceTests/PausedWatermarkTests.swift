import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §5.2a/§5.3 (v1.6): the founding scenario's FOURTH escape route, closed.
// A pause with a known end resumes by derivation and its resumed sequence
// materializes even while paused; an indefinite pause freezes the watermark so
// a manual resume can backfill from it. Before v1.6 the watermark advanced
// through every pause, leaving the resumed charges permanently unbackfillable.
extension SerializedPersistenceTests {
    @Suite("The watermark and the pause (spec §5.2a/§5.3, v1.6)")
    struct PausedWatermarkTests {

        private let instant = Date(timeIntervalSince1970: 8_000)

        @Test("an indefinite pause materializes nothing")
        func indefinitePauseMaterializesNothing() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 31), pauseEndsOn: .some(nil)
            )
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 5, at: instant
            )

            #expect(created == [])
            #expect(try await store.events(forSubscription: subscription.id) == [])
        }

        @Test("a pause with a known end materializes the resumed sequence while still paused (spec §5.2a, v1.6)")
        func datedPauseMaterializesResumedSequence() async throws {
            let (store, _) = try makeStore()
            // Monthly on the 1st, paused until Sep 1. As of Aug 6 the pause is still
            // running, but the resumed charges are already certain - their rows are
            // what make the watermark safe to advance while paused.
            let subscription = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 6, 1), pauseEndsOn: try day(2026, 9, 1)
            )
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            #expect(created.map(\.expectedDate) == [try day(2026, 9, 1), try day(2026, 10, 1), try day(2026, 11, 1)])
            #expect(created.allSatisfy { $0.expectedAmountCents == subscription.amountCents })
        }

        @Test("pause ending Sep 1, app unopened until Oct 15: both vendor charges get their rows")
        func foundingScenarioFourthEscapeRoute() async throws {
            let (store, _) = try makeStore()
            // Monthly on the 1st, paused in August until Sep 1. NOTHING runs until
            // Oct 15 - the vendor resumed on schedule and charged Sep 1 and Oct 1.
            let subscription = try makeSubscription(
                status: .paused,
                cycleStartDay: try day(2026, 6, 1),
                pauseEndsOn: try day(2026, 9, 1)
            )
            try await store.save(subscription)
            try await store.initializeMaterializationWatermark(
                forSubscription: subscription.id, at: try day(2026, 8, 20)
            )

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 10, 15), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            // Both charges that fell in the drawer, nothing from inside the pause.
            let dates = created.map(\.expectedDate)
            let resumeDay = try day(2026, 9, 1)
            #expect(dates.contains(resumeDay))
            #expect(dates.contains(try day(2026, 10, 1)))
            #expect(dates.allSatisfy { $0 >= resumeDay })
        }

        @Test("an indefinite pause freezes the watermark and leaves updatedAt alone")
        func indefinitePauseFreezesWatermark() async throws {
            let (store, _) = try makeStore()
            let frozen = try day(2026, 8, 1)
            let subscription = try makeSubscription(
                status: .paused,
                cycleStartDay: try day(2026, 1, 31),
                pauseEndsOn: .some(nil)
            )
            try await store.save(subscription)
            try await store.initializeMaterializationWatermark(
                forSubscription: subscription.id, at: frozen
            )

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 10, 15), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            #expect(created == [])
            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            #expect(try await store.materializationWatermark(forSubscription: subscription.id) == frozen)
            #expect(reloaded.updatedAt == subscription.updatedAt)
        }

        @Test("a manual resume backfills from the frozen watermark")
        func manualResumeBackfillsFromFrozenWatermark() async throws {
            let (store, _) = try makeStore()
            // Paused indefinitely with the watermark frozen at Aug 1; several passes
            // run during the pause and move nothing. The user resumes on Oct 15.
            let paused = try makeSubscription(
                status: .paused,
                cycleStartDay: try day(2026, 1, 31),
                pauseEndsOn: .some(nil)
            )
            try await store.save(paused)
            try await store.initializeMaterializationWatermark(
                forSubscription: paused.id, at: try day(2026, 8, 1)
            )
            _ = try await store.materializeEvents(
                for: paused, from: try day(2026, 9, 1), horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            let resumed = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(resumed)
            let created = try await store.materializeEvents(
                for: resumed, from: try day(2026, 10, 15), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            // The window reaches back to the freeze: Aug 31 and Sep 30 fell during
            // the gap and get their rows for the user to confirm or dismiss.
            let dates = created.map(\.expectedDate)
            #expect(dates.contains(try day(2026, 8, 31)))
            #expect(dates.contains(try day(2026, 9, 30)))
        }

        @Test("a pass during a dated pause advances the watermark safely - the resumed rows exist first")
        func datedPauseAdvancesWatermarkWithRowsInPlace() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(
                status: .paused,
                cycleStartDay: try day(2026, 6, 1),
                pauseEndsOn: try day(2026, 9, 1)
            )
            try await store.save(subscription)
            try await store.initializeMaterializationWatermark(
                forSubscription: subscription.id, at: try day(2026, 8, 1)
            )

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            #expect(created.map(\.expectedDate) == [try day(2026, 9, 1)])
            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            #expect(
                try await store.materializationWatermark(forSubscription: subscription.id)
                    == (try day(2026, 9, 5))
            )
            #expect(reloaded.updatedAt == subscription.updatedAt)
        }
    }
}
