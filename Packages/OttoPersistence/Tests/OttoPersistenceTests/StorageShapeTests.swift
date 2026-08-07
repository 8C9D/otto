import Foundation
import OttoDomain
import Testing
@testable import OttoPersistence

extension SerializedPersistenceTests {
    @Suite("Storage shapes: yyyymmdd days and two-scalar cycles")
    struct StorageShapeTests {

        @Test(
            "calendar days survive the yyyymmdd form exactly, including edge dates",
            arguments: [
                (2026, 8, 6, 20260806),
                (2024, 2, 29, 20240229),   // leap day
                (2026, 12, 31, 20261231),  // year boundary
                (2027, 1, 1, 20270101),    // year boundary, single-digit month and day
                (1, 1, 1, 10101),          // smallest representable day
                (9999, 12, 31, 99991231)   // largest representable day
            ]
        )
        func calendarDayRoundTrip(year: Int, month: Int, dayOfMonth: Int, encoded: Int) throws {
            let original = try day(year, month, dayOfMonth)
            #expect(original.yyyymmdd == encoded)
            #expect(CalendarDay(yyyymmdd: encoded) == original)
        }

        @Test("impossible yyyymmdd values decode to nil, not garbage", arguments: [20260230, 20261301, 20260800, 0, -20260806, 101])
        func calendarDayRejectsImpossible(encoded: Int) {
            #expect(CalendarDay(yyyymmdd: encoded) == nil)
        }

        @Test("a stored impossible date is a mapping error, not a crash")
        func calendarDayStoredThrows() {
            #expect(throws: MappingError.self) {
                try CalendarDay.stored(20260230, entity: "Test", field: "day")
            }
            #expect(throws: MappingError.self) {
                try CalendarDay.stored(nil, entity: "Test", field: "day")
            }
        }

        @Test("billing cycles survive the two-scalar form exactly", arguments: [
            BillingCycle.monthly, .quarterly, .annual, .weekly, .biweekly, .semiannual
        ])
        func billingCycleRoundTrip(original: BillingCycle) throws {
            let decoded = try BillingCycle.stored(
                unitRaw: original.unit.rawValue, interval: original.interval, entity: "Test"
            )
            #expect(decoded == original)
        }

        @Test("an every-45-days custom cycle survives the two-scalar form")
        func customCycleRoundTrip() throws {
            let original = try #require(BillingCycle(unit: .day, interval: 45))
            let decoded = try BillingCycle.stored(unitRaw: "day", interval: 45, entity: "Test")
            #expect(decoded == original)
        }

        @Test("unknown units and impossible intervals are mapping errors")
        func billingCycleRejects() {
            #expect(throws: MappingError.self) {
                try BillingCycle.stored(unitRaw: "fortnight", interval: 1, entity: "Test")
            }
            #expect(throws: MappingError.self) {
                try BillingCycle.stored(unitRaw: "month", interval: 0, entity: "Test")
            }
            #expect(throws: MappingError.self) {
                try BillingCycle.stored(unitRaw: nil, interval: 1, entity: "Test")
            }
            #expect(throws: MappingError.self) {
                try BillingCycle.stored(unitRaw: "month", interval: nil, entity: "Test")
            }
        }

        @Test("edge dates survive actual storage, not just the encoding")
        func edgeDatesThroughStore() async throws {
            let (store, _) = try makeStore()
            let leapAnchor = try makeSubscription(index: 1, cycle: .annual, cycleStartDay: try day(2024, 2, 29))
            try await store.save(leapAnchor)
            let loaded = try await store.subscription(withID: leapAnchor.id)
            #expect(loaded?.cycleStartDay == (try day(2024, 2, 29)))

            let event = try makeBillingEvent(subscriptionID: leapAnchor.id, expectedDate: try day(2026, 12, 31))
            try await store.save(event)
            let events = try await store.events(forSubscription: leapAnchor.id)
            #expect(events.first?.expectedDate == (try day(2026, 12, 31)))
        }
    }
}
