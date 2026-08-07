import Foundation
import Testing
import OttoDomain
@testable import OttoStores

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

/// The fixed "now" for the whole suite: 2026-08-06, instant 10_000.
func fixedDates(sourceLocation: SourceLocation = #_sourceLocation) throws -> DateProvider {
    .fixed(today: try day(2026, 8, 6), now: Date(timeIntervalSince1970: 10_000))
}

func makeSubscription(
    index: Int = 0,
    name: String? = nil,
    status: SubscriptionStatus = .active,
    amountCents: Int = 1099,
    cycle: BillingCycle = .monthly,
    cycleStartDay: CalendarDay,
    pauseEndsOn: CalendarDay? = nil,
    lastMaterializedThrough: CalendarDay? = nil,
    trial: TrialTerm? = nil,
    paymentMethodID: UUID? = nil
) throws -> Subscription {
    Subscription(
        id: try fixtureUUID(index),
        name: name ?? "Fixture \(index)",
        category: .other,
        status: status,
        amountCents: amountCents,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: 3,
        pauseEndsOn: pauseEndsOn,
        lastMaterializedThrough: lastMaterializedThrough,
        trial: trial,
        paymentMethodID: paymentMethodID,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func makeTrialTerm(
    index: Int = 500,
    startDate: CalendarDay,
    lengthDays: Int = 14,
    bufferDays: Int = 2,
    convertsToAmountCents: Int = 1599,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> TrialTerm {
    try #require(
        TrialTerm(
            id: try fixtureUUID(index),
            startDate: startDate,
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ),
        sourceLocation: sourceLocation
    )
}

func makeCancellationRecord(
    index: Int = 600,
    subscriptionID: UUID,
    nextChargeDateIfNotCancelled: CalendarDay,
    verificationState: CancellationRecord.VerificationState = .pending
) throws -> CancellationRecord {
    CancellationRecord(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        markedCancelledAt: Date(timeIntervalSince1970: 4_000),
        nextChargeDateIfNotCancelled: nextChargeDateIfNotCancelled,
        verificationState: verificationState,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func makeBillingEvent(
    index: Int = 700,
    subscriptionID: UUID,
    expectedDate: CalendarDay,
    expectedAmountCents: Int = 1099,
    state: BillingEvent.State = .upcoming
) throws -> BillingEvent {
    BillingEvent(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        expectedDate: expectedDate,
        expectedAmountCents: expectedAmountCents,
        state: state,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

/// The error every primed mock failure throws.
struct TestFailure: Error, Equatable {}
