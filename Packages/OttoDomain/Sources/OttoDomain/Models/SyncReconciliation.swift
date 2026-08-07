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

/// What merging one subscription's rival OPEN episodes decided: the surviving
/// episode (with the losers' notes and progress merged in) and the episodes to
/// tombstone - the same shape as the ledger merge, because it is the same
/// situation: two devices recorded one real-world act.
public struct CancellationRivalReconciliation: Hashable, Sendable {
    public let winner: CancellationEpisode
    public let loserIDs: [UUID]
}

extension CancellationEpisode {
    /// The convergence for multiple OPEN live episodes on one subscription -
    /// each side cancelled independently. One shape with the ledger rule and
    /// the pause repair (spec §4a principle 2a, unified in v2.1): the earliest
    /// `markedCancelledAt` (tie: id) survives, because the earliest
    /// cancellation is when the user actually acted, and its earlier check
    /// date errs toward watching sooner, never too late. The losers' evidence
    /// notes and verification progress merge into it; the losers themselves
    /// are tombstoned by the applying paths (the import merge and the
    /// post-sync reconciliation pass, which share this rule so they cannot
    /// drift). A loser's own note copies ride along under its tombstone as
    /// communicable history; the winner's copies are the live ones.
    /// Nil unless there are at least two rivals.
    public static func reconcilingOpenRivals(among open: [CancellationEpisode]) -> CancellationRivalReconciliation? {
        guard open.count > 1 else { return nil }
        let ordered = open.sorted {
            ($0.markedCancelledAt, $0.id.uuidString) < ($1.markedCancelledAt, $1.id.uuidString)
        }
        guard var winner = ordered.first else { return nil }
        let losers = ordered.dropFirst()

        var knownNoteIDs = Set(winner.evidenceNotes.map(\.id))
        for loser in losers {
            for note in loser.evidenceNotes where knownNoteIDs.insert(note.id).inserted {
                winner.evidenceNotes.append(note)
            }
        }
        // A rival that already observed the watch failing donates the
        // observation - un-observing a charge would be data loss. Adopted only
        // onto a `.pending` winner: `.awaitingResumeDate` cannot take a state
        // that requires a check date, and a winner past `.pending` made its
        // own observation, which a twin's does not overwrite.
        if winner.verificationState == .pending,
           let progressed = losers.first(where: {
               $0.verificationState == .stillCharging || $0.verificationState == .needsManualReview
           }) {
            winner.verificationState = progressed.verificationState
        }
        winner.unansweredCheckCount = max(
            winner.unansweredCheckCount, losers.map(\.unansweredCheckCount).max() ?? 0
        )
        // The two nil-means-legacy fields heal from any twin that recorded them.
        if winner.statusAtStart == nil {
            winner.statusAtStart = losers.compactMap(\.statusAtStart).first
        }
        if winner.expectedChargeAmountCents == nil {
            winner.expectedChargeAmountCents = losers.compactMap(\.expectedChargeAmountCents).first
        }
        return CancellationRivalReconciliation(winner: winner, loserIDs: losers.map(\.id))
    }
}
