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
    amountCents: Int = 1099,
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
        amountCents: amountCents,
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
        actualAmountCents: 1299,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

/// A validated, fully populated trial term.
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
    verificationState: CancellationRecord.VerificationState = .pending,
    unansweredCheckCount: Int = 0,
    evidenceNote: String? = nil
) throws -> CancellationRecord {
    CancellationRecord(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        markedCancelledAt: Date(timeIntervalSince1970: 4_000),
        nextChargeDateIfNotCancelled: nextChargeDateIfNotCancelled,
        verificationState: verificationState,
        unansweredCheckCount: unansweredCheckCount,
        evidenceNote: evidenceNote,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func makePriceChange(
    index: Int = 200,
    subscriptionID: UUID,
    effectiveDate: CalendarDay,
    source: PriceChange.Source = .userEdit,
    note: String? = nil
) throws -> PriceChange {
    PriceChange(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        effectiveDate: effectiveDate,
        oldAmountCents: 1099,
        newAmountCents: 1299,
        source: source,
        note: note,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func makePaymentMethod(index: Int = 300, label: String = "Bank Mastercard ..4821", isDefault: Bool = true) throws -> PaymentMethod {
    PaymentMethod(
        id: try fixtureUUID(index),
        label: label,
        last4: "4821",
        issuer: "Bank",
        expiryMonth: 11,
        expiryYear: 2027,
        isDefault: isDefault,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}
