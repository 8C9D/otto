import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §5.3 (v1.3): editing an anchor, cycle, or amount changes the sequence, and
// .upcoming rows for the old sequence are phantom charges. Invalidation tombstones
// them; re-materialization writes the new sequence as new records.
extension SerializedPersistenceTests {
    @Suite("Schedule-change invalidation (spec §5.3)")
    struct ScheduleChangeInvalidationTests {

        private let instant = Date(timeIntervalSince1970: 8_000)
        private let editInstant = Date(timeIntervalSince1970: 9_000)

        @Test("a price edit invalidates the old-amount rows, and re-materialization writes the new ones")
        func priceEditInvalidatesAndRematerializes() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            let created = try await store.materializeEvents(
                for: original, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            #expect(created.count == 3)

            // The user corrects the price: same anchor, same cycle, new amount.
            let edited = try makeSubscription(amountCents: 1299, cycleStartDay: try day(2026, 1, 15))
            try await store.save(edited)

            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )
            #expect(invalidated.count == 3)
            #expect(invalidated.allSatisfy { $0.deletedAt == editInstant })

            // The old rows are gone from live reads; the new sequence lands on the same
            // dates as NEW records at the new amount, not resurrections.
            let rematerialized = try await store.materializeEvents(
                for: edited, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: editInstant
            )
            #expect(rematerialized.map(\.expectedDate) == created.map(\.expectedDate))
            #expect(rematerialized.allSatisfy { $0.expectedAmountCents == 1299 })
            #expect(Set(rematerialized.map(\.id)).isDisjoint(with: Set(created.map(\.id))))

            let live = try await store.events(forSubscription: edited.id)
            #expect(live.allSatisfy { $0.expectedAmountCents == 1299 })
            #expect(live.count == 3)
        }

        @Test("an anchor edit tombstones every old-sequence row and only those")
        func anchorEditInvalidatesOldDates() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            _ = try await store.materializeEvents(
                for: original, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            // The 15th was wrong; the vendor bills the 20th.
            let edited = try makeSubscription(cycleStartDay: try day(2026, 1, 20))
            try await store.save(edited)
            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )
            #expect(invalidated.map(\.expectedDate) == [try day(2026, 8, 15), try day(2026, 9, 15), try day(2026, 10, 15)])

            let rematerialized = try await store.materializeEvents(
                for: edited, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: editInstant
            )
            #expect(rematerialized.map(\.expectedDate) == [try day(2026, 8, 20), try day(2026, 9, 20), try day(2026, 10, 20)])
        }

        @Test("rows in any state but .upcoming are never touched - a confirmed charge is history")
        func confirmedRowsAreHistory() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            // A confirmed charge from the old sequence - not on the new sequence's dates.
            try await store.save(
                try makeBillingEvent(index: 100, subscriptionID: original.id, expectedDate: try day(2026, 7, 15))
            )

            let edited = try makeSubscription(cycleStartDay: try day(2026, 1, 20))
            try await store.save(edited)
            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )

            #expect(invalidated.isEmpty)
            let events = try await store.events(forSubscription: edited.id)
            #expect(events.map(\.expectedDate) == [try day(2026, 7, 15)])
            #expect(events.first?.deletedAt == nil)
        }

        @Test("an unchanged schedule invalidates nothing - the operation is idempotent")
        func unchangedScheduleIsUntouched() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            _ = try await store.materializeEvents(
                for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: subscription, asOf: today, at: editInstant
            )
            #expect(invalidated.isEmpty)
            #expect(try await store.events(forSubscription: subscription.id).count == 3)
        }

        @Test(
            "a transition into a non-expecting status invalidates every .upcoming row (spec §5.3, v1.4)",
            arguments: [SubscriptionStatus.cancellationPending, .cancelled, .archived]
        )
        func statusTransitionInvalidates(status: SubscriptionStatus) async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            let created = try await store.materializeEvents(
                for: original, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            #expect(created.count == 3)

            // The subscription stops expecting charges; without invalidation the user
            // sees phantom charges in Detail for a subscription that will not charge.
            let transitioned = try makeSubscription(status: status, cycleStartDay: try day(2026, 1, 15))
            try await store.save(transitioned)
            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: transitioned, asOf: today, at: editInstant
            )

            #expect(invalidated.map(\.expectedDate) == created.map(\.expectedDate))
            #expect(try await store.events(forSubscription: transitioned.id).isEmpty)
        }

        @Test("an indefinite pause invalidates every .upcoming row (spec §5.3, v1.4/v1.6)")
        func indefinitePauseInvalidates() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            let created = try await store.materializeEvents(
                for: original, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            #expect(created.count == 3)

            let paused = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: .some(nil)
            )
            try await store.save(paused)
            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: paused, asOf: today, at: editInstant
            )

            #expect(invalidated.map(\.expectedDate) == created.map(\.expectedDate))
            #expect(try await store.events(forSubscription: paused.id).isEmpty)
        }

        @Test("a dated pause invalidates only the rows inside the pause - the resumed sequence keeps its rows (spec §5.2a, v1.6)")
        func datedPauseKeepsResumedRows() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let original = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(original)
            let created = try await store.materializeEvents(
                for: original, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            #expect(created.map(\.expectedDate) == [try day(2026, 8, 15), try day(2026, 9, 15), try day(2026, 10, 15)])

            // Paused until Oct 1: Aug 15 and Sep 15 fall inside the pause and are
            // phantoms; Oct 15 belongs to the resumed sequence and stays.
            let paused = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: try day(2026, 10, 1)
            )
            try await store.save(paused)
            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: paused, asOf: today, at: editInstant
            )

            #expect(invalidated.map(\.expectedDate) == [try day(2026, 8, 15), try day(2026, 9, 15)])
            #expect(try await store.events(forSubscription: paused.id).map(\.expectedDate) == [try day(2026, 10, 15)])
        }

        @Test("resuming from .paused re-materializes - tombstoned .upcoming rows never block (spec §5.3)")
        func resumeFromPauseRematerializes() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let active = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(active)
            let created = try await store.materializeEvents(
                for: active, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )

            let paused = try makeSubscription(
                status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: .some(nil)
            )
            try await store.save(paused)
            _ = try await store.invalidateOutdatedUpcomingEvents(for: paused, asOf: today, at: editInstant)
            #expect(try await store.events(forSubscription: paused.id).isEmpty)

            let resumed = try makeSubscription(cycleStartDay: try day(2026, 1, 15))
            try await store.save(resumed)
            let rematerialized = try await store.materializeEvents(
                for: resumed, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: editInstant
            )

            #expect(rematerialized.map(\.expectedDate) == created.map(\.expectedDate))
            #expect(Set(rematerialized.map(\.id)).isDisjoint(with: Set(created.map(\.id))))
        }

        @Test("an unconverted trial's conversion row survives only while it matches the term")
        func trialConversionRowInvalidation() async throws {
            let (store, _) = try makeStore()
            let today = try day(2026, 8, 6)
            let trial = try makeTrialTerm(startDate: today, lengthDays: 14, convertsToAmountCents: 1100)
            let subscription = try makeSubscription(status: .trial, cycleStartDay: today, trial: trial)
            try await store.save(subscription)
            let created = try await store.materializeEvents(
                for: subscription, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: instant
            )
            #expect(created.map(\.expectedDate) == [trial.conversionDate])

            // The user corrects the trial length: the conversion moves, the old row is
            // a phantom.
            let editedTrial = try makeTrialTerm(startDate: today, lengthDays: 30, convertsToAmountCents: 1100)
            let edited = try makeSubscription(status: .trial, cycleStartDay: today, trial: editedTrial)
            try await store.save(edited)

            let invalidated = try await store.invalidateOutdatedUpcomingEvents(
                for: edited, asOf: today, at: editInstant
            )
            #expect(invalidated.map(\.expectedDate) == [trial.conversionDate])

            let rematerialized = try await store.materializeEvents(
                for: edited, from: today, horizonDays: 90, maxReminderLeadDays: 0, at: editInstant
            )
            #expect(rematerialized.map(\.expectedDate) == [editedTrial.conversionDate])
        }
    }
}
