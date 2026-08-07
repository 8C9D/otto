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

    /// Creates the `.upcoming` rows for every charge date inside
    /// `today...today+horizonDays+maxReminderLeadDays` that has no row yet, per spec
    /// §5.3: a row is materialized when its reminder is scheduled, never earlier, and
    /// the REMINDER window governs - a reminder inside the horizon can belong to a
    /// charge just outside it, so the charge window is wider by the largest lead time
    /// in use. An active subscription materializes its cycle sequence; a trial
    /// materializes exactly one row, at its conversion date, for the converted
    /// amount. Idempotent - a date that already has a row, live or tombstoned, is
    /// never re-created. Returns only the newly created events, stamped with
    /// `instant` as their audit instants (the store never reads a clock). Wave 2
    /// owns this creation path; Wave 4 owns calling it from the reminder scheduler.
    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent]
}
