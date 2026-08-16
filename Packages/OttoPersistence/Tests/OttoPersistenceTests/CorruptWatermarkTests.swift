import Foundation
import OSLog
import SwiftData
import Testing
@testable import OttoPersistence

/// R0-5. A corrupt stored watermark read as the same nil an ABSENT one
/// produces, and neither path logged. A nil watermark sends `materializeEvents`
/// back to today (`OttoStore+BillingEvents.swift`), so the rows between the last
/// real charge and today are silently never created - F6's exact signature, by a
/// third route with no record that it happened.
///
/// Measured at HEAD before the fix, against a real device store:
///
///     PROBE absent             -> nil
///     PROBE corrupt(20260230)  -> nil
///     PROBE corrupt(0)         -> nil
///     PROBE same as absent?    true
extension SerializedPersistenceTests {
    @Suite("A watermark that is not a date (R0-5)")
    struct CorruptWatermarkTests {

        /// Writes a raw packed value the public API cannot produce - which is
        /// the point: the writers that can are `setDeviceWatermark`, which
        /// packs a validated `CalendarDay`, and the V2→V3 migration, which
        /// carries the old column across WITHOUT validating it.
        private func seedRawWatermark(
            _ value: Int?, forSubscription subscriptionID: UUID, in containers: OttoContainers
        ) throws {
            let context = ModelContext(containers.deviceState)
            let row = StoredMaterializationWatermark()
            context.insert(row)
            row.subscriptionID = subscriptionID
            row.lastMaterializedThrough = value
            try context.save()
        }

        @Test("⛔ an unreadable watermark is logged; an absent one is not")
        func corruptIsLoggedAndAbsentIsNot() async throws {
            let (store, containers) = try makeStore()
            let corruptID = try fixtureUUID(1)
            let absentID = try fixtureUUID(2)

            let since = Date()
            let canary = OttoLogProbe.emitCanary()
            // Absent first: it must stay silent, or the log stops meaning
            // anything - every scheduling pass reads a watermark.
            _ = try await store.materializationWatermark(forSubscription: absentID)
            try seedRawWatermark(20_260_230, forSubscription: corruptID, in: containers)
            let read = try await store.materializationWatermark(forSubscription: corruptID)

            // Still nil: there is nothing safe to invent from a value that is
            // not a date, and guessing later would vouch for rows that may not
            // exist. What changed is that it says so.
            #expect(read == nil)

            let lines = try OttoLogProbe.persistenceLines(since: since)
            try OttoLogProbe.requireDelivered(lines, canary: canary)
            let mine = corruptID.uuidString.lowercased()
            let line = try #require(
                lines.last { $0.contains("watermark unreadable") && $0.lowercased().contains(mine) },
                "an unreadable watermark was read and nothing was written down"
            )
            #expect(line.contains("20260230"))
            #expect(!line.lowercased().contains(absentID.uuidString.lowercased()))
        }

        @Test("⛔ a corrupt row must not shadow a readable one beside it")
        func aCorruptRowDoesNotShadowAReadableOne() async throws {
            let (store, containers) = try makeStore()
            let subscriptionID = try fixtureUUID(3)
            // Zero is smaller than every real packed day, so a `min` taken over
            // the raw Ints picks it and the readable row is discarded - which
            // reads as nil and materializes from TODAY, the exact failure this
            // suite exists to remove a route into. `reviews-3/REVIEW-4.md`
            // finding 2 measured it: nil here, `2026-06-01` under the pre-fix
            // `rows.first`, so the first version of the fix was WORSE than what
            // it replaced for this input.
            try seedRawWatermark(20_260_601, forSubscription: subscriptionID, in: containers)
            try seedRawWatermark(0, forSubscription: subscriptionID, in: containers)

            #expect(
                try await store.materializationWatermark(forSubscription: subscriptionID)
                    == (try day(2026, 6, 1))
            )
        }

        @Test("a row whose only value is unreadable still reads as nil")
        func aLoneUnreadableRowIsNil() async throws {
            let (store, containers) = try makeStore()
            let subscriptionID = try fixtureUUID(6)
            // Characterisation, not a regression guard: `CalendarDay(yyyymmdd: 0)`
            // was already nil before this item. It is here because the branch
            // above must not turn "nothing readable" into something invented.
            try seedRawWatermark(0, forSubscription: subscriptionID, in: containers)
            #expect(try await store.materializationWatermark(forSubscription: subscriptionID) == nil)
        }

        @Test("⛔ duplicate rows resolve to the EARLIEST, deterministically")
        func duplicateRowsTakeTheMinimum() async throws {
            let (store, containers) = try makeStore()
            let subscriptionID = try fixtureUUID(4)
            // No unique constraint exists (CloudKit forbids one) and the fetch
            // is unsorted, so `rows.first` was a coin toss between these two.
            try seedRawWatermark(20_261_130, forSubscription: subscriptionID, in: containers)
            try seedRawWatermark(20_260_601, forSubscription: subscriptionID, in: containers)

            let read = try await store.materializationWatermark(forSubscription: subscriptionID)
            #expect(read == (try day(2026, 6, 1)))
        }

        @Test("⛔ an unreadable value cannot pin a reconstruction to itself")
        func reconstructionIgnoresAnUnreadableCap() async throws {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(index: 5, cycleStartDay: try day(2026, 3, 1))
            try await store.save(subscription)
            // The v2.5 cap is a min over RAW Ints. Zero is smaller than every
            // real packed day, so before this fix it survived every
            // reconstruction and the subscription could never recover.
            try seedRawWatermark(0, forSubscription: subscription.id, in: containers)

            try await store.reconstructMaterializationWatermarks()

            #expect(
                try await store.materializationWatermark(forSubscription: subscription.id)
                    == (try day(2026, 3, 1))
            )
        }
    }
}
