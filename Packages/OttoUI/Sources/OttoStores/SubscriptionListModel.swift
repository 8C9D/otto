import Foundation
import Observation
import OttoDomain

/// Sorting and filtering for the Subscriptions screen (spec §7.1 item 2). The
/// arithmetic behind every column - the next relevant date, the monthly
/// equivalent - comes from the domain; this model only composes comparators.
@MainActor
@Observable
public final class SubscriptionListModel {

    public enum SortOrder: String, CaseIterable, Sendable {
        case nextDate, cost, name, category
    }

    /// nil filters nothing.
    public var statusFilter: SubscriptionStatus?
    public var sortOrder: SortOrder = .nextDate

    public init() {}

    /// One list row: the subscription with its precomputed display facts, so the
    /// view renders values rather than deriving them.
    public struct Row: Identifiable, Hashable, Sendable {
        public let subscription: Subscription
        /// The status the row displays and the filter matches - effective, not
        /// stored (spec §5.2a, v1.7): a resumed pause rows as Active, a
        /// converted trial rows as Active, because that is the state the user
        /// is actually in.
        public let effectiveStatus: SubscriptionStatus
        /// The next date that matters for this subscription - next charge, trial
        /// conversion, pause resume, or verification check - via `todayEntry`.
        public let nextDate: CalendarDay?
        /// Spec §7.2's normalisation, so a $120/yr and a $10/mo compare at a glance.
        public let monthlyEquivalentCents: Int

        public var id: UUID { subscription.id }
    }

    public func rows(
        subscriptions: [Subscription],
        cancellations: [UUID: CancellationRecord],
        today: CalendarDay
    ) -> [Row] {
        let filtered = subscriptions.filter { subscription in
            statusFilter.map { subscription.effectiveStatus(asOf: today) == $0 } ?? true
        }
        let rows = filtered.map { subscription in
            Row(
                subscription: subscription,
                effectiveStatus: subscription.effectiveStatus(asOf: today),
                nextDate: todayEntry(
                    for: subscription, cancellation: cancellations[subscription.id], from: today
                )?.date,
                monthlyEquivalentCents: monthlyEquivalentCents(
                    amountCents: subscription.amountCents, cycle: subscription.cycle
                )
            )
        }
        return rows.sorted { lhs, rhs in
            isOrdered(lhs, rhs) || (!isOrdered(rhs, lhs) && lhs.id.uuidString < rhs.id.uuidString)
        }
    }

    /// Strict ordering for the active sort key alone; ties fall through to id.
    private func isOrdered(_ lhs: Row, _ rhs: Row) -> Bool {
        switch sortOrder {
        case .nextDate:
            // Dateless rows (archived, indefinitely paused) sink to the bottom.
            switch (lhs.nextDate, rhs.nextDate) {
            case (let lhsDate?, let rhsDate?): lhsDate < rhsDate
            case (.some, nil): true
            case (nil, .some), (nil, nil): false
            }
        case .cost:
            // Most expensive first - the order the question "what is costing me?" wants.
            lhs.monthlyEquivalentCents > rhs.monthlyEquivalentCents
        case .name:
            lhs.subscription.name.localizedCaseInsensitiveCompare(rhs.subscription.name) == .orderedAscending
        case .category:
            lhs.subscription.category.rawValue < rhs.subscription.category.rawValue
        }
    }
}
