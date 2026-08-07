import Foundation
import OttoDomain
import OttoRepositories
import SwiftData

extension OttoStore: ReconciliationRepository {

    /// The post-sync convergence pass (spec §5.3 v2.0, §4a): merge duplicate
    /// ledger twins, close rival open cancellation episodes, and persist any
    /// §4a read repairs - all by pure domain rules, so every device converges
    /// on the same state without coordination. One save at the end; a failure
    /// anywhere leaves the store as it was.
    public func reconcile(at instant: Date) async throws -> ReconciliationSummary {
        var summary = ReconciliationSummary()
        try mergeDuplicateLedgerRows(at: instant, into: &summary)
        try closeRivalCancellationEpisodes(into: &summary)
        try persistReadRepairs(into: &summary)
        if modelContext.hasChanges {
            try modelContext.save()
        }
        return summary
    }

    /// Live twins on one `(subscriptionID, expectedDate)`: the domain rule
    /// picks the survivor and folds acknowledgement/confirmation state in;
    /// this pass writes the merge and tombstones the losers at `instant`.
    private func mergeDuplicateLedgerRows(
        at instant: Date, into summary: inout ReconciliationSummary
    ) throws {
        let live = try modelContext.fetch(
            FetchDescriptor<StoredBillingEvent>(predicate: #Predicate { $0.deletedAt == nil })
        )
        var groups: [String: [StoredBillingEvent]] = [:]
        for record in live {
            guard let subscriptionID = record.subscriptionID, let date = record.expectedDate else { continue }
            groups["\(subscriptionID.uuidString)/\(date)", default: []].append(record)
        }
        for records in groups.values where records.count > 1 {
            let rows = mapSkippingFailures(records) { try $0.toDomain() }
            guard let merged = BillingEvent.reconcilingDuplicates(rows) else { continue }
            let recordsByID = Dictionary(
                records.compactMap { record in record.id.map { ($0, record) } },
                uniquingKeysWith: { first, _ in first }
            )
            if let winnerRecord = recordsByID[merged.winner.id],
               (try? winnerRecord.toDomain()) != merged.winner {
                var stamped = merged.winner
                stamped.updatedAt = instant
                winnerRecord.update(from: stamped)
            }
            for loserID in merged.loserIDs {
                guard let loser = recordsByID[loserID] else { continue }
                loser.deletedAt = instant
                loser.updatedAt = instant
            }
            summary.mergedLedgerGroups += 1
        }
    }

    /// Two open live episodes on one subscription: the shared §5.3a rule (one
    /// rule with the import merge) keeps the newest open and returns the rest
    /// closed as `.superseded`; this pass writes them back.
    private func closeRivalCancellationEpisodes(into summary: inout ReconciliationSummary) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<StoredCancellationEpisode>(predicate: #Predicate { $0.deletedAt == nil })
        )
        var openBySubscription: [UUID: [CancellationEpisode]] = [:]
        for episode in mapSkippingFailures(records, { try $0.toDomain() }) where episode.isOpen {
            openBySubscription[episode.subscriptionID, default: []].append(episode)
        }
        let recordsByID = Dictionary(
            records.compactMap { record in record.id.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        for rivals in openBySubscription.values {
            for closed in CancellationEpisode.closingSupersededRivals(among: rivals) {
                guard let record = recordsByID[closed.id] else { continue }
                record.update(from: closed)
                summary.closedCancellationEpisodes += 1
            }
        }
    }

    /// Subscriptions whose read applied a §4a repair that CHANGED data (a
    /// closed pause episode): write the repaired value back, so convergence is
    /// durable rather than re-derived on every read. The two held shapes
    /// (`.paused`/.`trial` awaiting a child) persist nothing - there is
    /// nothing to write, they self-heal when the child arrives.
    private func persistReadRepairs(into summary: inout ReconciliationSummary) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<StoredSubscription>(predicate: #Predicate { $0.deletedAt == nil })
        )
        for record in records {
            var repairs: [SubscriptionReadRepair] = []
            guard let repaired = try? record.toDomain(collecting: &repairs) else { continue }
            let persistable = repairs.contains { repair in
                switch repair {
                case .extraOpenPauseEpisodeClosed, .conflictingOpenPauseEpisodeClosed: true
                case .pausedWithoutOpenEpisode, .trialWithoutTerm: false
                }
            }
            if persistable {
                record.update(from: repaired)
                summary.persistedReadRepairs += 1
            }
        }
    }
}
