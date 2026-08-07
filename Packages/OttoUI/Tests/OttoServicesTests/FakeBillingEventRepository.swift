import Foundation
import OttoDomain
import OttoRepositories
@testable import OttoServices

/// In-memory ledger with the same materialization and invalidation semantics as
/// the SwiftData store - both defer every decision to the domain's
/// `expectedCharges`/`isExpectedCharge`, so the fake stays honest without
/// dragging SwiftData into this target. Call counters let scheduler tests assert
/// upkeep happens at scheduling time (spec §5.3).
actor FakeBillingEventRepository: BillingEventRepository {
    private var stored: [UUID: BillingEvent] = [:]
    private var watermarks: [UUID: CalendarDay] = [:]
    private(set) var invalidateCalls: [UUID] = []
    private(set) var materializeCalls: [UUID] = []

    func seed(_ events: [BillingEvent]) {
        for event in events { stored[event.id] = event }
    }

    /// Test seeding: the direct write the production protocol deliberately
    /// does not offer (only initialise-once and rewind exist there).
    func seedWatermark(_ day: CalendarDay?, forSubscription subscriptionID: UUID) {
        watermarks[subscriptionID] = day
    }

    func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay? {
        watermarks[subscriptionID]
    }

    func initializeMaterializationWatermark(
        forSubscription subscriptionID: UUID, at day: CalendarDay
    ) async throws {
        if watermarks[subscriptionID] == nil { watermarks[subscriptionID] = day }
    }

    func rewindMaterializationWatermark(
        forSubscription subscriptionID: UUID, to day: CalendarDay
    ) async throws {
        if let current = watermarks[subscriptionID], day < current { watermarks[subscriptionID] = day }
    }

    func save(_ event: BillingEvent) async throws {
        stored[event.id] = event
    }

    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        try await eventsIncludingDeleted(forSubscription: subscriptionID)
            .filter { $0.deletedAt == nil }
    }

    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] {
        stored.values
            .filter { $0.subscriptionID == subscriptionID }
            .sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }

    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent] {
        materializeCalls.append(subscription.id)
        guard subscription.deletedAt == nil, horizonDays >= 0, maxReminderLeadDays >= 0 else {
            return []
        }
        // The watermark freezes where the store's does (spec §5.3): an
        // indefinite pause, and any cancellation state - their exits re-expect
        // charges retroactively, so nothing may vouch for the frozen window.
        let effective = subscription.effectiveStatus(asOf: today)
        if effective == .paused && subscription.pauseEndsOn == nil { return [] }
        if effective == .cancellationPending || effective == .cancelled { return [] }
        // The window reaches back to the STORED watermark, mirroring the store
        // (spec §5.3, v1.5; device state since Wave 6B-Prep).
        let charges = expectedCharges(
            for: subscription,
            from: min(watermarks[subscription.id] ?? today, today),
            through: today.adding(days: horizonDays + maxReminderLeadDays),
            asOf: today
        )
        // Dedup mirrors the store: live rows and non-.upcoming tombstones block;
        // tombstoned .upcoming rows are invalidation artifacts and do not.
        let blockedDates = Set(
            stored.values
                .filter { $0.subscriptionID == subscription.id }
                .filter { $0.deletedAt == nil || $0.state != .upcoming }
                .map(\.expectedDate)
        )
        var created: [BillingEvent] = []
        for charge in charges where !blockedDates.contains(charge.day) {
            let event = BillingEvent(
                id: UUID(),
                subscriptionID: subscription.id,
                expectedDate: charge.day,
                expectedAmountCents: charge.amountCents,
                state: .upcoming,
                createdAt: instant,
                updatedAt: instant
            )
            stored[event.id] = event
            created.append(event)
        }
        return created
    }

    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent] {
        invalidateCalls.append(subscription.id)
        var invalidated: [BillingEvent] = []
        for var event in stored.values
        where event.subscriptionID == subscription.id && event.deletedAt == nil && event.state == .upcoming {
            if isExpectedCharge(
                day: event.expectedDate, amountCents: event.expectedAmountCents,
                for: subscription, asOf: today
            ) { continue }
            event.deletedAt = instant
            event.updatedAt = instant
            stored[event.id] = event
            invalidated.append(event)
        }
        return invalidated.sorted { ($0.expectedDate, $0.id.uuidString) < ($1.expectedDate, $1.id.uuidString) }
    }
}
