import Foundation
import Testing
import OttoDomain

/// Unwraps a validated `CalendarDay`, failing the calling test at its own line when the
/// date is impossible.
func day(
    _ year: Int,
    _ month: Int,
    _ dayOfMonth: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CalendarDay {
    try #require(CalendarDay(year: year, month: month, day: dayOfMonth), sourceLocation: sourceLocation)
}

/// Unwraps a validated `BillingCycle` for cadences without a named static.
func cycle(
    _ unit: BillingCycle.Unit,
    _ interval: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> BillingCycle {
    try #require(BillingCycle(unit: unit, interval: interval), sourceLocation: sourceLocation)
}

/// A deterministic UUID so fixture failures reproduce identically run to run.
func fixtureUUID(
    _ index: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> UUID {
    let uuidString = String(format: "00000000-0000-0000-0000-%012d", index)
    return try #require(UUID(uuidString: uuidString), sourceLocation: sourceLocation)
}

/// A validated trial term with fixture audit fields, so tests state only the
/// values they vary.
func makeTrialTerm(
    index: Int = 500,
    startDate: CalendarDay,
    lengthDays: Int,
    bufferDays: Int = 2,
    convertsToAmountCents: Int = 1100,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> TrialTerm {
    try #require(
        TrialTerm(
            id: try fixtureUUID(index),
            startDate: startDate,
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        ),
        sourceLocation: sourceLocation
    )
}

/// A subscription fixture exposing only the fields the scheduling tests vary.
func makeSubscription(
    index: Int = 0,
    status: SubscriptionStatus,
    cycle: BillingCycle,
    cycleStartDay: CalendarDay,
    reminderLeadDays: Int = 3,
    pauseEndsOn: CalendarDay? = nil,
    trial: TrialTerm? = nil,
    lastUsedDate: CalendarDay? = nil
) throws -> Subscription {
    Subscription(
        id: try fixtureUUID(index),
        name: "Fixture \(index)",
        category: .other,
        status: status,
        amountCents: 1099,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: reminderLeadDays,
        pauseEndsOn: pauseEndsOn,
        trial: trial,
        lastUsedDate: lastUsedDate,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
