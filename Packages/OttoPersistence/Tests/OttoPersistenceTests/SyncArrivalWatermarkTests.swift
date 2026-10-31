import Foundation
import OttoDomain
import OttoRepositories
import Testing
@testable import OttoPersistence

/// Watermarks never sync, so on a device where sync has been on, a nil watermark
/// means the record ARRIVED (spec §5.3, Wave 6B). Starting those from today is
/// the founding hazard reached through iCloud.
extension SerializedPersistenceTests {
    @Suite("The watermark of a record that arrived by sync")
    struct SyncArrivalWatermarkTests {
        private let instant = Date(timeIntervalSince1970: 20_000)

        @Test("once sync has been on, a nil watermark means an ARRIVAL: the pass starts at the ledger's edge, not today")
        func arrivalBackfillsFromTheLedgerEdge() async throws {
            // The reinstall path: the phone was lost in March, iCloud gave the
            // subscription and its ledger back in August, and watermarks never
            // sync. Starting from today silently loses April through July.
            let (store, _) = try makeStore(syncState: SyncState(isEnabled: true))
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)
            try await store.save(try makeBillingEvent(
                index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 3, 31)
            ))

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            #expect(created.map(\.expectedDate) == [
                try day(2026, 4, 30), try day(2026, 5, 31), try day(2026, 6, 30),
                try day(2026, 7, 31), try day(2026, 8, 31)
            ])
        }

        @Test("an arrival with no ledger yet starts at its entry day - never inventing history before it")
        func arrivalWithNoLedgerStartsAtEntryDay() async throws {
            let (store, _) = try makeStore(syncState: SyncState(isEnabled: true))
            // Anchored in 2024, entered on 2026-06-10. The device that created
            // it never backfilled 2024-2026; this one must not either.
            var subscription = try makeSubscription(cycleStartDay: try day(2024, 1, 15))
            subscription.createdAt = try #require(ISO8601DateFormatter().date(from: "2026-06-10T12:00:00Z"))
            try await store.save(subscription)

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )

            #expect(created.map(\.expectedDate) == [
                try day(2026, 6, 15), try day(2026, 7, 15), try day(2026, 8, 15)
            ])
        }

        @Test("the kill switch does not turn an arrival back into a pre-v1.5 record")
        func arrivalSurvivesTheKillSwitch() async throws {
            let (store, _) = try makeStore(syncState: SyncState(isEnabled: true, killSwitchEngaged: true))
            let subscription = try makeSubscription(cycleStartDay: try day(2026, 1, 31))
            try await store.save(subscription)
            try await store.save(try makeBillingEvent(
                index: 101, subscriptionID: subscription.id, expectedDate: try day(2026, 7, 31)
            ))

            let created = try await store.materializeEvents(
                for: subscription, from: try day(2026, 8, 6), horizonDays: 30, maxReminderLeadDays: 0, at: instant
            )
            #expect(created.map(\.expectedDate) == [try day(2026, 8, 31)])
            // Under the today rule the same dates appear, so pin the watermark
            // path too: it advanced, and the next pass re-reads no window.
            #expect(try await store.materializationWatermark(forSubscription: subscription.id) != nil)
        }
    }
}
