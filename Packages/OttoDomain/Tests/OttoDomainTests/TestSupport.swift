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

func makeCancellationEpisode(
    index: Int = 600,
    subscriptionID: UUID,
    nextChargeDateIfNotCancelled: CalendarDay,
    expectedChargeAmountCents: Int? = 1099,
    verificationState: CancellationEpisode.VerificationState = .pending,
    endedAt: Date? = nil,
    outcome: CancellationEpisode.Outcome? = nil
) throws -> CancellationEpisode {
    CancellationEpisode(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        markedCancelledAt: Date(timeIntervalSince1970: 0),
        nextChargeDateIfNotCancelled: nextChargeDateIfNotCancelled,
        expectedChargeAmountCents: expectedChargeAmountCents,
        verificationState: verificationState,
        endedAt: endedAt,
        outcome: outcome,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

/// An open pause episode fixture (spec §5.3a) - what a paused subscription's
/// current pause looks like in tests.
func makePauseEpisode(
    index: Int = 700,
    startedOn: CalendarDay? = nil,
    scheduledResumeOn: CalendarDay? = nil,
    endedOn: CalendarDay? = nil,
    outcome: PauseEpisode.Outcome? = nil
) throws -> PauseEpisode {
    PauseEpisode(
        id: try fixtureUUID(index),
        startedOn: startedOn,
        scheduledResumeOn: scheduledResumeOn,
        endedOn: endedOn,
        outcome: outcome,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

/// A subscription fixture exposing only the fields the scheduling tests vary.
/// The v1.7-era `pausedOn`/`pauseEndsOn` parameters survive as the open pause
/// episode they now describe (spec §5.3a), so tests keep stating pause state
/// in the two values that matter.
func makeSubscription(
    index: Int = 0,
    status: SubscriptionStatus,
    cycle: BillingCycle = .monthly,
    cycleStartDay: CalendarDay,
    reminderLeadDays: Int = 3,
    sameDayReminder: Bool = false,
    pauseEndsOn: CalendarDay? = nil,
    pausedOn: CalendarDay? = nil,
    pauseEpisodes: [PauseEpisode]? = nil,
    lastMaterializedThrough: CalendarDay? = nil,
    trial: TrialTerm? = nil,
    lastUsedDate: CalendarDay? = nil
) throws -> Subscription {
    let episodes: [PauseEpisode]
    if let pauseEpisodes {
        episodes = pauseEpisodes
    } else if status == .paused || pausedOn != nil || pauseEndsOn != nil {
        episodes = [try makePauseEpisode(
            index: index + 700, startedOn: pausedOn, scheduledResumeOn: pauseEndsOn
        )]
    } else {
        episodes = []
    }
    return Subscription(
        id: try fixtureUUID(index),
        name: "Fixture \(index)",
        category: .other,
        status: status,
        amountCents: 1099,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: reminderLeadDays,
        sameDayReminder: sameDayReminder,
        pauseEpisodes: episodes,
        lastMaterializedThrough: lastMaterializedThrough,
        trial: trial,
        lastUsedDate: lastUsedDate,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
