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
    /// in use. Statuses act EFFECTIVELY (spec §5.2a): an active subscription - or a
    /// trial whose conversion date has passed, anchored at conversion for the
    /// converted amount - materializes its cycle sequence; an unconverted trial
    /// materializes exactly one row, at its conversion date. Idempotent - a date
    /// with a live row, or a tombstoned row in any state but `.upcoming`, is never
    /// re-created; tombstoned `.upcoming` rows are §5.3 invalidation artifacts and
    /// do not block, because the new sequence's rows are new records. Returns only
    /// the newly created events, stamped with `instant` as their audit instants
    /// (the store never reads a clock). Wave 4 owns calling this from the reminder
    /// scheduler.
    func materializeEvents(
        for subscription: Subscription,
        from today: CalendarDay,
        horizonDays: Int,
        maxReminderLeadDays: Int,
        at instant: Date
    ) async throws -> [BillingEvent]

    /// Spec §5.3 (v1.3): soft-deletes every live `.upcoming` row that no longer
    /// matches the subscription's effective charge sequence - the phantom charges a
    /// changed anchor, cycle, or amount leaves behind. Rows in any other state are
    /// never touched: a confirmed charge is history. Returns the invalidated events.
    /// Callers re-materialize afterwards; the scheduler (Wave 4) runs both on save.
    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription,
        asOf today: CalendarDay,
        at instant: Date
    ) async throws -> [BillingEvent]

    // MARK: - The device watermark (spec §5.3, Wave 6B-Prep)

    // The materialization watermark is device state the domain value no longer
    // carries - one authority, the device store. These are the ONLY mutations a
    // flow can express: initialise-once and rewind. Neither can advance an
    // existing watermark, because a watermark vouches that every expected
    // charge through it has a row, and only a ledger pass may claim that.

    /// This device's watermark for one subscription: the last day through which
    /// a ledger pass here has observed its expected charges. Nil when no pass
    /// has ever observed it on this device.
    func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay?

    /// Writes the watermark only when none exists - the entry initialisation
    /// (spec §5.3, v1.5: the later of the anchor and the entry day, so Mode B
    /// never backfills history it had no rows for). A subscription that already
    /// has a watermark is left exactly as it was, in both directions.
    func initializeMaterializationWatermark(
        forSubscription subscriptionID: UUID, at day: CalendarDay
    ) async throws

    /// Moves the watermark to `min(stored, day)`: a watermark at or behind `day`,
    /// or absent, is untouched. Rewinding is safe by construction - a regressed
    /// watermark re-observes idempotently, while an advanced one vouches for
    /// rows that may not exist (spec §5.3).
    func rewindMaterializationWatermark(
        forSubscription subscriptionID: UUID, to day: CalendarDay
    ) async throws
}
