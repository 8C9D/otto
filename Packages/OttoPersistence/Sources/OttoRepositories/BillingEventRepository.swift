import Foundation
import OttoDomain

/// Layer 3 access to the billing ledger (spec §5.3).
public protocol BillingEventRepository: Sendable {
    /// Inserts or updates by `id`. Throws `RepositoryError.subscriptionNotFound`
    /// when the event's subscription has no persisted record.
    func save(_ event: BillingEvent) async throws

    /// Live events for one subscription, ordered by expected date.
    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent]

    /// All events for one subscription including tombstones.
    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent]

    /// Creates the `.upcoming` rows for every billing date inside
    /// `today...today+horizonDays` that has no row yet, per spec §5.3: a row is
    /// materialized when its reminder is scheduled, never earlier. Idempotent -
    /// a date that already has a row, live or tombstoned, is never re-created.
    /// Returns only the newly created events. Wave 2 owns this creation path;
    /// Wave 4 owns calling it from the reminder scheduler.
    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int
    ) async throws -> [BillingEvent]
}
