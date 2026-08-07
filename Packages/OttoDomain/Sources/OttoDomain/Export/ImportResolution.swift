import Foundation

/// What happens when an import meets a non-empty database. There is no silent
/// default: the UI asks, because either answer discards something and only the
/// user knows which loss is intended (Wave 8: never silently discard user data).
public enum ImportStrategy: String, Hashable, Sendable, CaseIterable {
    /// The file and the database are combined. Records only one side has are
    /// kept; when both have a record with the same id, the newer `updatedAt`
    /// wins - the last-write-wins resolution §3.5's timestamps exist for. A tie
    /// keeps the existing record, so importing your own fresh export is a no-op.
    case merge
    /// The database becomes exactly what the file describes. Existing records
    /// are removed - stated, counted, and confirmed in the UI, never implied.
    case replace
}

/// What an import did, per entity: the numbers the UI states so nothing about
/// the outcome is left to inference.
public struct ImportCounts: Hashable, Sendable {
    /// Records from the file that did not exist in the database.
    public var added = 0
    /// Existing records overwritten by a newer copy from the file - including
    /// open cancellation episodes a merge closed as `.superseded` because a
    /// newer open one claimed the same subscription (spec §5.3a).
    public var updated = 0
    /// File records skipped because the database copy was newer or equal.
    public var skippedOlder = 0
    /// Existing records removed (replace strategy only - merge never discards).
    public var removed = 0

    public init(added: Int = 0, updated: Int = 0, skippedOlder: Int = 0, removed: Int = 0) {
        self.added = added
        self.updated = updated
        self.skippedOlder = skippedOlder
        self.removed = removed
    }
}

public struct ImportSummary: Hashable, Sendable {
    public var subscriptions = ImportCounts()
    public var paymentMethods = ImportCounts()
    public var billingEvents = ImportCounts()
    public var cancellationEpisodes = ImportCounts()
    public var priceChanges = ImportCounts()

    public init() {}
}

public struct ResolvedImport: Hashable, Sendable {
    /// The complete database state the import produces - the persistence layer
    /// applies it atomically as a whole.
    public let snapshot: OttoDataSnapshot
    public let summary: ImportSummary
}

/// Resolves an imported snapshot against the current database into the exact
/// state to persist. Pure - every decision is here and testable; the store only
/// applies the result.
///
/// Watermarks: neither the file nor the snapshot carries one (spec §5.3, Wave
/// 6B-Prep: the watermark lives only in the device store). A merge leaves this
/// device's ledger progress untouched; a replace resets it (the import flow
/// calls the device-store reset), because after the database becomes exactly
/// what the file describes, past observation vouches for rows the file may not
/// carry.
public func resolveImport(
    current: OttoDataSnapshot,
    incoming: OttoDataSnapshot,
    strategy: ImportStrategy
) throws -> ResolvedImport {
    var summary = ImportSummary()
    var resolved = OttoDataSnapshot()

    switch strategy {
    case .replace:
        resolved = incoming
        summary.subscriptions = replaceCounts(current: current.subscriptions, incoming: incoming.subscriptions)
        summary.paymentMethods = replaceCounts(current: current.paymentMethods, incoming: incoming.paymentMethods)
        summary.billingEvents = replaceCounts(current: current.billingEvents, incoming: incoming.billingEvents)
        summary.cancellationEpisodes = replaceCounts(
            current: current.cancellationEpisodes, incoming: incoming.cancellationEpisodes
        )
        summary.priceChanges = replaceCounts(current: current.priceChanges, incoming: incoming.priceChanges)
    case .merge:
        resolved.subscriptions = merge(
            current: current.subscriptions, incoming: incoming.subscriptions,
            counts: &summary.subscriptions
        )
        resolved.paymentMethods = merge(
            current: current.paymentMethods, incoming: incoming.paymentMethods,
            counts: &summary.paymentMethods
        )
        resolved.billingEvents = merge(
            current: current.billingEvents, incoming: incoming.billingEvents,
            counts: &summary.billingEvents
        )
        resolved.cancellationEpisodes = merge(
            current: current.cancellationEpisodes, incoming: incoming.cancellationEpisodes,
            counts: &summary.cancellationEpisodes
        )
        resolved.priceChanges = merge(
            current: current.priceChanges, incoming: incoming.priceChanges,
            counts: &summary.priceChanges
        )
        resolveSingleOpenCancellation(in: &resolved, counts: &summary.cancellationEpisodes)
    }

    try validate(resolved)
    normalizeSingleDefaultPaymentMethod(in: &resolved)
    return ResolvedImport(snapshot: resolved, summary: summary)
}

// MARK: - Record identity

/// The two facts resolution needs from every record type.
private protocol ImportableRecord {
    var id: UUID { get }
    var updatedAt: Date { get }
}

extension Subscription: ImportableRecord {}
extension PaymentMethod: ImportableRecord {}
extension BillingEvent: ImportableRecord {}
extension CancellationEpisode: ImportableRecord {}
extension PriceChange: ImportableRecord {}

// MARK: - The merge

private func merge<Record: ImportableRecord>(
    current: [Record],
    incoming: [Record],
    counts: inout ImportCounts,
    resolvingConflict: (_ existing: Record, _ incoming: Record) -> Record = { _, incoming in incoming }
) -> [Record] {
    let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    var result = current
    for record in incoming {
        guard let existing = currentByID[record.id] else {
            counts.added += 1
            result.append(record)
            continue
        }
        if record.updatedAt > existing.updatedAt {
            counts.updated += 1
            let winner = resolvingConflict(existing, record)
            if let index = result.firstIndex(where: { $0.id == record.id }) {
                result[index] = winner
            }
        } else {
            counts.skippedOlder += 1
        }
    }
    return result
}

private func replaceCounts<Record: ImportableRecord>(
    current: [Record], incoming: [Record]
) -> ImportCounts {
    let currentIDs = Set(current.map(\.id))
    let incomingIDs = Set(incoming.map(\.id))
    return ImportCounts(
        added: incomingIDs.subtracting(currentIDs).count,
        updated: incomingIDs.intersection(currentIDs).count,
        removed: currentIDs.subtracting(incomingIDs).count
    )
}

// MARK: - Structural repairs the domain model requires

/// At most one cancellation episode per subscription is OPEN (spec §5.3a). A
/// merge can legitimately unite two open ones (each side cancelled
/// independently, different ids): `closingSupersededRivals` - one rule with
/// the post-sync reconciliation pass - keeps the newest open and closes the
/// others with `.superseded` at its start instant, recorded as what happened
/// rather than deleted, and COUNTED as updated so nothing about the outcome
/// is silent. This is the episode-table win over v1's single slot: the losing
/// side's cancellation used to be discarded outright; now it stays history.
private func resolveSingleOpenCancellation(in snapshot: inout OttoDataSnapshot, counts: inout ImportCounts) {
    var openBySubscription: [UUID: [CancellationEpisode]] = [:]
    for episode in snapshot.cancellationEpisodes where episode.isOpen && episode.deletedAt == nil {
        openBySubscription[episode.subscriptionID, default: []].append(episode)
    }
    for (_, rivals) in openBySubscription {
        for closed in CancellationEpisode.closingSupersededRivals(among: rivals) {
            guard let index = snapshot.cancellationEpisodes.firstIndex(where: { $0.id == closed.id }) else {
                continue
            }
            snapshot.cancellationEpisodes[index] = closed
            counts.updated += 1
        }
    }
}

/// Merging two databases can leave two live default cards; the invariant the
/// stores enforce is re-established here the same way: newest default wins.
private func normalizeSingleDefaultPaymentMethod(in snapshot: inout OttoDataSnapshot) {
    let liveDefaults = snapshot.paymentMethods.filter { $0.isDefault && $0.deletedAt == nil }
    guard liveDefaults.count > 1 else { return }
    let winner = liveDefaults.max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    for index in snapshot.paymentMethods.indices
    where snapshot.paymentMethods[index].isDefault && snapshot.paymentMethods[index].id != winner?.id {
        snapshot.paymentMethods[index].isDefault = false
    }
}

/// Referential integrity before anything touches the store: every child names a
/// subscription the resolved state actually contains, and no subscription has
/// two OPEN cancellation episodes (spec §5.3a: at most one is current - closed
/// history can pile up freely).
private func validate(_ snapshot: OttoDataSnapshot) throws {
    let subscriptionIDs = Set(snapshot.subscriptions.map(\.id))
    for event in snapshot.billingEvents where !subscriptionIDs.contains(event.subscriptionID) {
        throw ExportFormatError.danglingReference(
            entity: "billingEvent \(event.id)", subscriptionID: event.subscriptionID
        )
    }
    for record in snapshot.cancellationEpisodes where !subscriptionIDs.contains(record.subscriptionID) {
        throw ExportFormatError.danglingReference(
            entity: "cancellationEpisode \(record.id)", subscriptionID: record.subscriptionID
        )
    }
    for change in snapshot.priceChanges where !subscriptionIDs.contains(change.subscriptionID) {
        throw ExportFormatError.danglingReference(
            entity: "priceChange \(change.id)", subscriptionID: change.subscriptionID
        )
    }
    var openClaimed: Set<UUID> = []
    for episode in snapshot.cancellationEpisodes where episode.isOpen && episode.deletedAt == nil {
        guard openClaimed.insert(episode.subscriptionID).inserted else {
            throw ExportFormatError.duplicateCancellation(subscriptionID: episode.subscriptionID)
        }
    }
}
