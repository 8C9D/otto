import Foundation

// The post-sync reconciliation rules (spec §5.3 v2.0, §5.3a) - pure decisions,
// so the store pass and the import merge apply ONE rule and every device
// reaches the same result independently. Prevention-only dedup was sufficient
// in a single-writer world; enabling sync ends that world, and these are the
// reconciliations that end needs.

/// What merging one duplicate ledger group decided: the surviving row (with
/// state merged from the rest) and the rows to tombstone.
public struct LedgerGroupReconciliation: Hashable, Sendable {
    public let winner: BillingEvent
    public let loserIDs: [UUID]
}

extension BillingEvent {
    /// The §5.3 merge for LIVE rows sharing one `(subscriptionID,
    /// expectedDate)` - the shape two devices materializing the same charge
    /// date produce, which write-time dedup prevents locally but can never
    /// reconcile after arrival. Nil unless there are at least two rows.
    ///
    /// Deterministic by construction: the earliest `createdAt` wins (tie: id),
    /// and the merge folds the rest in a fixed order. Any acknowledgement
    /// counts - the user said "keeping it" on SOME copy, and re-asking on the
    /// surviving row would un-silence a reminder they silenced. Any
    /// confirmation counts, for the same reason: the earliest-created
    /// non-`.upcoming` twin donates its state, `userConfirmedAt`, and
    /// `actualAmountCents`. A winner that is already confirmed keeps its own
    /// answer - the user confirmed THIS row.
    public static func reconcilingDuplicates(_ rows: [BillingEvent]) -> LedgerGroupReconciliation? {
        guard rows.count > 1 else { return nil }
        let ordered = rows.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        guard var winner = ordered.first else { return nil }
        let losers = ordered.dropFirst()

        if winner.acknowledgedAt == nil {
            winner.acknowledgedAt = losers.compactMap(\.acknowledgedAt).min()
        }
        if winner.state == .upcoming,
           let confirmed = losers.first(where: { $0.state != .upcoming }) {
            winner.state = confirmed.state
            winner.userConfirmedAt = confirmed.userConfirmedAt
            winner.actualAmountCents = confirmed.actualAmountCents
        }
        return LedgerGroupReconciliation(winner: winner, loserIDs: losers.map(\.id))
    }
}

extension CancellationEpisode {
    /// The §5.3a convergence for multiple OPEN live episodes on one
    /// subscription - each side cancelled independently. The newest
    /// `markedCancelledAt` (tie: id) stays open; the rest come back CLOSED
    /// with `.superseded` at the winner's start - recorded as what happened
    /// rather than deleted. One rule, shared by the import merge and the
    /// post-sync reconciliation pass, so the two paths cannot drift.
    public static func closingSupersededRivals(among open: [CancellationEpisode]) -> [CancellationEpisode] {
        guard open.count > 1 else { return [] }
        let ordered = open.sorted {
            ($0.markedCancelledAt, $0.id.uuidString) > ($1.markedCancelledAt, $1.id.uuidString)
        }
        guard let winner = ordered.first else { return [] }
        return ordered.dropFirst().map { loser in
            var closed = loser
            closed.endedAt = winner.markedCancelledAt
            closed.outcome = .superseded
            closed.updatedAt = winner.markedCancelledAt
            return closed
        }
    }
}
