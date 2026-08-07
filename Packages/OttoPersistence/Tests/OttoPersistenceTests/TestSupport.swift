import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

/// Unwraps a validated `CalendarDay`, failing the calling test at its own line.
func day(
    _ year: Int,
    _ month: Int,
    _ dayOfMonth: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CalendarDay {
    try #require(CalendarDay(year: year, month: month, day: dayOfMonth), sourceLocation: sourceLocation)
}

/// A deterministic UUID so fixture failures reproduce identically run to run.
func fixtureUUID(
    _ index: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> UUID {
    let uuidString = String(format: "00000000-0000-0000-0000-%012d", index)
    return try #require(UUID(uuidString: uuidString), sourceLocation: sourceLocation)
}

/// A fresh isolated in-memory store per test.
func makeStore() throws -> (store: OttoStore, container: ModelContainer) {
    let container = try OttoContainerFactory.inMemoryContainer()
    return (OttoStore(modelContainer: container), container)
}

/// A fully populated subscription so round-trips exercise every field.
func makeSubscription(
    index: Int = 0,
    status: SubscriptionStatus = .active,
    cycle: BillingCycle = .monthly,
    cycleStartDay: CalendarDay,
    trial: TrialTerm? = nil,
    deletedAt: Date? = nil
) throws -> Subscription {
    Subscription(
        id: try fixtureUUID(index),
        name: "Fixture \(index)",
        vendorURL: URL(string: "https://example.com/account"),
        category: .foodAndDelivery,
        status: status,
        amountCents: 1099,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: 3,
        sameDayReminder: true,
        pauseEndsOn: status == .paused ? cycleStartDay.adding(days: 60) : nil,
        trial: trial,
        paymentMethodID: try fixtureUUID(900),
        cancellationURL: URL(string: "https://example.com/cancel"),
        cancellationNotes: "phone only, mention retention offer",
        lastUsedDate: cycleStartDay.adding(days: 10),
        notes: "a note",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000),
        deletedAt: deletedAt
    )
}

func makeBillingEvent(index: Int = 100, subscriptionID: UUID, expectedDate: CalendarDay) throws -> BillingEvent {
    BillingEvent(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        expectedDate: expectedDate,
        expectedAmountCents: 1099,
        state: .confirmedCharged,
        userConfirmedAt: Date(timeIntervalSince1970: 3_000),
        actualAmountCents: 1299
    )
}
