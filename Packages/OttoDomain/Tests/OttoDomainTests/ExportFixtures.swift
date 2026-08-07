import Foundation
import Testing
@testable import OttoDomain

// MARK: - The full-fidelity export fixture

// Instants carry fractional seconds so round-trips prove bit-exact, not just
// second-exact.
private let fixtureCreated = Date(timeIntervalSinceReferenceDate: 776_304_000.123456)
private let fixtureUpdated = Date(timeIntervalSinceReferenceDate: 776_390_412.654321)
private let fixtureDeleted = Date(timeIntervalSinceReferenceDate: 776_400_001.000111)

/// A database exercising every model type, every enum case that can appear in
/// one, soft-deleted rows, multi-year price history, trials at each state, and
/// cancellations at every verification state - the round-trip fixture Wave 8
/// requires.
func fullSnapshot() throws -> OttoDataSnapshot {
    OttoDataSnapshot(
        subscriptions: [
            // Confirmed conversion: active, retained term, watermark set.
            try exportSubscription(
                1, status: .active, cycle: .monthly, category: .foodAndDelivery,
                watermark: try day(2026, 9, 1),
                trial: try exportTrialTerm(501, startDate: try day(2024, 1, 17))
            ),
            try exportSubscription(
                2, status: .trial, cycle: .weekly, category: .musicAndAudio,
                trial: try exportTrialTerm(502, startDate: try day(2026, 8, 1))
            ),
            // Converted-unflipped: stored .trial, conversion long past.
            try exportSubscription(
                3, status: .trial, cycle: try cycle(.day, 45), category: .aiAndSoftwareTools,
                trial: try exportTrialTerm(503, startDate: try day(2026, 1, 1))
            ),
            try exportSubscription(
                4, status: .paused, cycle: try cycle(.year, 1), category: .gaming,
                pauseEndsOn: try day(2026, 12, 1), pausedOn: try day(2026, 6, 1)
            ),
            try exportSubscription(5, status: .paused, cycle: .quarterly, pausedOn: try day(2026, 5, 1)),
            try exportSubscription(6, status: .cancellationPending, cycle: .monthly),
            try exportSubscription(7, status: .cancellationPending, cycle: .biweekly),
            try exportSubscription(8, status: .cancelled, cycle: .semiannual),
            try exportSubscription(9, status: .cancelled, cycle: .monthly),
            try exportSubscription(10, status: .archived, cycle: .monthly),
            try exportSubscription(11, status: .active, cycle: .monthly, deletedAt: fixtureDeleted)
        ],
        paymentMethods: [
            PaymentMethod(
                id: try fixtureUUID(300), label: "Bank Mastercard ..4821", last4: "4821",
                issuer: "Bank", expiryMonth: 11, expiryYear: 2027, isDefault: true,
                createdAt: fixtureCreated, updatedAt: fixtureUpdated
            ),
            PaymentMethod(
                id: try fixtureUUID(301), label: "Amex ..0005", last4: "0005",
                issuer: "Amex", expiryMonth: 2, expiryYear: 2029, isDefault: false,
                createdAt: fixtureCreated, updatedAt: fixtureUpdated, deletedAt: fixtureDeleted
            )
        ],
        billingEvents: try exportBillingEvents(),
        cancellationRecords: [
            try exportCancellation(601, subscription: 6, state: .pending, checkDate: try day(2026, 9, 1)),
            try exportCancellation(602, subscription: 7, state: .awaitingResumeDate, checkDate: nil),
            try exportCancellation(603, subscription: 8, state: .stillCharging, checkDate: try day(2026, 7, 1)),
            try exportCancellation(604, subscription: 9, state: .needsManualReview, checkDate: try day(2026, 6, 1)),
            try exportCancellation(605, subscription: 10, state: .verifiedStopped, checkDate: try day(2026, 5, 1))
        ],
        priceChanges: try exportPriceChanges()
    )
}

/// The snapshot as an import must reproduce it: identical except the
/// device-local watermark, which the file never carries (spec §5.3).
func strippingWatermarks(_ snapshot: OttoDataSnapshot) -> OttoDataSnapshot {
    var stripped = snapshot
    stripped.subscriptions = snapshot.subscriptions.map { subscription in
        var copy = subscription
        copy.lastMaterializedThrough = nil
        return copy
    }
    return stripped
}

// MARK: - Builders

private func exportSubscription(
    _ index: Int,
    status: SubscriptionStatus,
    cycle: BillingCycle,
    category: OttoDomain.Category = .streamingAndVideo,
    pauseEndsOn: CalendarDay? = nil,
    pausedOn: CalendarDay? = nil,
    watermark: CalendarDay? = nil,
    trial: TrialTerm? = nil,
    deletedAt: Date? = nil
) throws -> Subscription {
    Subscription(
        id: try fixtureUUID(index),
        name: "Vendor \(index), \"quoted\"",
        vendorURL: URL(string: "https://example.com/\(index)"),
        category: category,
        status: status,
        amountCents: 1099 + index,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: try day(2024, 1, 31),
        reminderLeadDays: 3,
        sameDayReminder: index.isMultiple(of: 2),
        pauseEndsOn: pauseEndsOn,
        pausedOn: pausedOn,
        lastMaterializedThrough: watermark,
        trial: trial,
        paymentMethodID: try fixtureUUID(300),
        cancellationURL: URL(string: "https://example.com/cancel/\(index)"),
        cancellationNotes: "phone only,\nmention retention offer",
        lastUsedDate: try day(2026, 7, 1),
        notes: "entered from the June statement",
        createdAt: fixtureCreated,
        updatedAt: fixtureUpdated,
        deletedAt: deletedAt
    )
}

private func exportTrialTerm(
    _ index: Int, startDate: CalendarDay, deletedAt: Date? = nil
) throws -> TrialTerm {
    try #require(TrialTerm(
        id: try fixtureUUID(index),
        startDate: startDate,
        lengthDays: 14,
        bufferDays: 2,
        convertsToAmountCents: 1599,
        createdAt: fixtureCreated,
        updatedAt: fixtureUpdated,
        deletedAt: deletedAt
    ))
}

private func exportCancellation(
    _ index: Int, subscription: Int,
    state: CancellationRecord.VerificationState,
    checkDate: CalendarDay?
) throws -> CancellationRecord {
    CancellationRecord(
        id: try fixtureUUID(index),
        subscriptionID: try fixtureUUID(subscription),
        markedCancelledAt: fixtureCreated,
        nextChargeDateIfNotCancelled: checkDate,
        expectedChargeAmountCents: checkDate == nil ? nil : 1099,
        verificationState: state,
        unansweredCheckCount: state == .needsManualReview ? 3 : 0,
        verifiedAt: state == .verifiedStopped ? fixtureUpdated : nil,
        evidenceNote: "conf #ABC-123",
        createdAt: fixtureCreated,
        updatedAt: fixtureUpdated
    )
}

/// Every billing-event state, one tombstone, fractional-second instants.
private func exportBillingEvents() throws -> [BillingEvent] {
    try zip(
        12 ... 17,
        [BillingEvent.State.upcoming, .confirmedCharged, .confirmedNotCharged,
         .unexpectedCharge, .skipped, .confirmedCharged]
    ).map { index, state in
        BillingEvent(
            id: try fixtureUUID(100 + index),
            subscriptionID: try fixtureUUID(1),
            expectedDate: try day(2026, 1, index),
            expectedAmountCents: 1099,
            state: state,
            userConfirmedAt: state == .confirmedCharged ? fixtureUpdated : nil,
            acknowledgedAt: index.isMultiple(of: 2) ? fixtureUpdated : nil,
            actualAmountCents: state == .unexpectedCharge ? 1299 : nil,
            createdAt: fixtureCreated,
            updatedAt: fixtureUpdated,
            deletedAt: index == 17 ? fixtureDeleted : nil
        )
    }
}

/// Multi-year history, every source, one tombstone.
private func exportPriceChanges() throws -> [PriceChange] {
    try zip(
        [(2024, PriceChange.Source.trialConversion, nil as Date?),
         (2025, .userEdit, nil),
         (2026, .chargeMismatch, fixtureDeleted)],
        201 ... 203
    ).map { entry, index in
        let (year, source, deletedAt) = entry
        return PriceChange(
            id: try fixtureUUID(index),
            subscriptionID: try fixtureUUID(1),
            effectiveDate: try day(year, 3, 1),
            oldAmountCents: 999 + index,
            newAmountCents: 1099 + index,
            source: source,
            note: source == .chargeMismatch ? "vendor raised it quietly" : nil,
            createdAt: fixtureCreated,
            updatedAt: fixtureUpdated,
            deletedAt: deletedAt
        )
    }
}
