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
///
/// The counts describe LIVE records only (Wave 10, defect H): a tombstone is
/// sync bookkeeping, not recovered data, and a restore summary that counts
/// tombstones as "added" overstates - which is worse than understating,
/// because it produces confidence in data that was never recovered. Each
/// count is a visibility transition: added = not-live before, live after;
/// updated = live before and after with the file's copy winning; removed =
/// live before, not live after. Pure tombstone movements count nowhere.
public struct ImportCounts: Hashable, Sendable {
    /// Live records from the file that were not live in the database -
    /// including a record the file resurrects over a local tombstone.
    public var added = 0
    /// Live records overwritten by a newer live copy from the file - including
    /// the surviving winner of rival open cancellation episodes a merge
    /// reconciled (spec §4a principle 2a).
    public var updated = 0
    /// Live file records skipped because the live database copy was newer or
    /// equal.
    public var skippedOlder = 0
    /// Previously-live records that are no longer live: everything a replace
    /// drops, a newer tombstone winning a merge (a deletion propagating), and
    /// the tombstoned losers of a rival-cancellation reconciliation.
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

    /// Records - either side's, embedded children included - that arrived with
    /// `updatedAt` or `deletedAt` BEFORE their own `createdAt`, the shape a
    /// set-back device clock writes (docs/sync-safety.md), raised to
    /// `createdAt` before anything compared them. Counted rather than silently
    /// merged on: a merge that decided on repaired stamps must be able to say
    /// so.
    public var timestampOrderRepairs = 0
    /// Records carrying a stamp AHEAD of the import instant, clamped to it. A
    /// future stamp is sticky under last-write-wins - it beats every honest
    /// edit until real time catches up - so the import defuses it and counts
    /// it.
    public var futureStampClamps = 0

    public init() {}
}

public struct ResolvedImport: Hashable, Sendable {
    /// The complete database state the import produces - the persistence layer
    /// applies it atomically as a whole.
    public let snapshot: OttoDataSnapshot
    public let summary: ImportSummary
}

/// Resolves an imported snapshot against the current database into the exact
/// state to persist. Every decision is here and testable; the store only
/// applies the result. `instant` stamps the audit fields of records the §4a
/// rival-cancellation merge writes, and caps the stamps an import will merge on
/// (docs/sync-safety.md) - every choice of which record wins is a pure function
/// of the record data.
///
/// Watermarks: neither the file nor the snapshot carries one (spec §5.3, Wave
/// 6B-Prep: the watermark lives only in the device store). A merge leaves this
/// device's ledger progress untouched; after a replace the import flow orders
/// the device-store reconstruction from the imported ledger (spec §5.3, v2.1),
/// because past observation vouches for rows the file may not carry.
public func resolveImport(
    current: OttoDataSnapshot,
    incoming: OttoDataSnapshot,
    strategy: ImportStrategy,
    at instant: Date
) throws -> ResolvedImport {
    var summary = ImportSummary()
    var resolved = OttoDataSnapshot()
    // Both sides, before any rule compares them: the merge reads stamps as
    // causal order and the device clock does not supply one
    // (docs/sync-safety.md). The order repair is a pure function of the record,
    // so every device reaches the same answer without coordination; only the
    // future clamp uses `instant`, because an import IS a write and a
    // write-time defence may use the write instant.
    var current = current
    var incoming = incoming
    repairStamps(in: &current, notAfter: instant, into: &summary)
    repairStamps(in: &incoming, notAfter: instant, into: &summary)

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
        resolveSingleOpenCancellation(in: &resolved, counts: &summary.cancellationEpisodes, at: instant)
    }

    try validate(resolved)
    normalizeSingleDefaultPaymentMethod(in: &resolved)
    return ResolvedImport(snapshot: resolved, summary: summary)
}

// MARK: - Stamp repair (docs/sync-safety.md)

/// The audit stamps every record carries - the ones the merge rules read as
/// causal order, and therefore the ones an import repairs before reading them.
private protocol StampedRecord {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension Subscription: StampedRecord {}
extension TrialTerm: StampedRecord {}
extension PauseEpisode: StampedRecord {}
extension PaymentMethod: StampedRecord {}
extension BillingEvent: StampedRecord {}
extension CancellationEpisode: StampedRecord {}
extension EvidenceNote: StampedRecord {}
extension PriceChange: StampedRecord {}

/// Every record on one side, embedded children included: a subscription's trial
/// and pause episodes and an episode's evidence notes travel inside their
/// parent but carry stamps of their own, and a future `createdAt` on a pause
/// episode is a clock value the §4a read repair would promote into a calendar
/// day.
private func repairStamps(
    in snapshot: inout OttoDataSnapshot, notAfter instant: Date, into summary: inout ImportSummary
) {
    for index in snapshot.subscriptions.indices {
        repairStamps(of: &snapshot.subscriptions[index], notAfter: instant, into: &summary)
        if var trial = snapshot.subscriptions[index].trial {
            repairStamps(of: &trial, notAfter: instant, into: &summary)
            snapshot.subscriptions[index].trial = trial
        }
        for child in snapshot.subscriptions[index].pauseEpisodes.indices {
            repairStamps(of: &snapshot.subscriptions[index].pauseEpisodes[child], notAfter: instant, into: &summary)
        }
    }
    for index in snapshot.paymentMethods.indices {
        repairStamps(of: &snapshot.paymentMethods[index], notAfter: instant, into: &summary)
    }
    for index in snapshot.billingEvents.indices {
        repairStamps(of: &snapshot.billingEvents[index], notAfter: instant, into: &summary)
    }
    for index in snapshot.cancellationEpisodes.indices {
        repairStamps(of: &snapshot.cancellationEpisodes[index], notAfter: instant, into: &summary)
        for child in snapshot.cancellationEpisodes[index].evidenceNotes.indices {
            repairStamps(
                of: &snapshot.cancellationEpisodes[index].evidenceNotes[child], notAfter: instant, into: &summary
            )
        }
    }
    for index in snapshot.priceChanges.indices {
        repairStamps(of: &snapshot.priceChanges[index], notAfter: instant, into: &summary)
    }
}

/// One record's two repairs, each counting the record once.
///
/// Order first: a stamp before its own `createdAt` is raised TO `createdAt`,
/// never the other way round - `createdAt` is the stamp the ledger merge orders
/// on, and moving it would rewrite which twin counts as the original. Then the
/// future clamp, which lowers whatever sits ahead of the import instant; a
/// future `createdAt` therefore ends up carrying its raised siblings down with
/// it, and all three land on `instant` together.
private func repairStamps<Record: StampedRecord>(
    of record: inout Record, notAfter instant: Date, into summary: inout ImportSummary
) {
    var repaired = false
    if record.updatedAt < record.createdAt {
        record.updatedAt = record.createdAt
        repaired = true
    }
    if let deleted = record.deletedAt, deleted < record.createdAt {
        record.deletedAt = record.createdAt
        repaired = true
    }
    if repaired { summary.timestampOrderRepairs += 1 }

    var clamped = false
    if record.createdAt > instant {
        record.createdAt = instant
        clamped = true
    }
    if record.updatedAt > instant {
        record.updatedAt = instant
        clamped = true
    }
    if let deleted = record.deletedAt, deleted > instant {
        record.deletedAt = instant
        clamped = true
    }
    if clamped { summary.futureStampClamps += 1 }
}

// MARK: - Record identity

/// The three facts resolution needs from every record type.
private protocol ImportableRecord {
    var id: UUID { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
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
            // A tombstone the file carries and the database lacks is applied
            // but not counted - it is sync bookkeeping, not recovered data
            // (Wave 10, defect H).
            if record.deletedAt == nil { counts.added += 1 }
            result.append(record)
            continue
        }
        if record.updatedAt > existing.updatedAt {
            // Count the visibility transition the winning copy causes.
            switch (existing.deletedAt == nil, record.deletedAt == nil) {
            case (true, true): counts.updated += 1
            case (true, false): counts.removed += 1
            case (false, true): counts.added += 1
            case (false, false): break
            }
            let winner = resolvingConflict(existing, record)
            if let index = result.firstIndex(where: { $0.id == record.id }) {
                result[index] = winner
            }
        } else if existing.deletedAt == nil && record.deletedAt == nil {
            counts.skippedOlder += 1
        }
    }
    return result
}

private func replaceCounts<Record: ImportableRecord>(
    current: [Record], incoming: [Record]
) -> ImportCounts {
    // Live sets only (Wave 10, defect H): the field run reported "4 added"
    // while three subscriptions existed anywhere in the app, because the
    // export's fourth carried `deletedAt`. The DATA was right - per-record
    // sync needs tombstones (§4a) - but the count vouched for a record the
    // user cannot see, in the one summary whose job is saying a restore
    // worked. Computing every count over live ids also makes a live record
    // the file carries only as a tombstone count as removed, which it is.
    let currentLive = Set(current.filter { $0.deletedAt == nil }.map(\.id))
    let incomingLive = Set(incoming.filter { $0.deletedAt == nil }.map(\.id))
    return ImportCounts(
        added: incomingLive.subtracting(currentLive).count,
        updated: incomingLive.intersection(currentLive).count,
        removed: currentLive.subtracting(incomingLive).count
    )
}

// MARK: - Structural repairs the domain model requires

/// At most one cancellation episode per subscription is OPEN (spec §5.3a). A
/// merge can legitimately unite two open ones (each side cancelled
/// independently, different ids): `reconcilingOpenRivals` - one rule with the
/// post-sync reconciliation pass, one shape with the ledger merge (spec §4a
/// principle 2a) - keeps the earliest, MOVES the losers' notes and folds
/// their progress into it, and tombstones the emptied losers at `instant`,
/// each write COUNTED so nothing about the outcome is silent: the winner as
/// updated, each tombstoned loser as removed, since a live episode stopped
/// being visible (Wave 10, defect H). (Spec §5.0a: the loser is tombstoned
/// holding none, so no note id ever names records under two parents.) The
/// tombstone carries a fresh `updatedAt` so it outranks any still-live copy
/// of the loser under last-write-wins rather than being resurrected by one.
private func resolveSingleOpenCancellation(
    in snapshot: inout OttoDataSnapshot, counts: inout ImportCounts, at instant: Date
) {
    var openBySubscription: [UUID: [CancellationEpisode]] = [:]
    for episode in snapshot.cancellationEpisodes where episode.isOpen && episode.deletedAt == nil {
        openBySubscription[episode.subscriptionID, default: []].append(episode)
    }
    for (_, rivals) in openBySubscription {
        guard let merged = CancellationEpisode.reconcilingOpenRivals(among: rivals) else { continue }
        if let index = snapshot.cancellationEpisodes.firstIndex(where: { $0.id == merged.winner.id }),
           snapshot.cancellationEpisodes[index] != merged.winner {
            var stamped = merged.winner
            stamped.updatedAt = monotonicStamp(instant, notBefore: stamped.updatedAt)
            snapshot.cancellationEpisodes[index] = stamped
            counts.updated += 1
        }
        for loser in merged.losers {
            guard let index = snapshot.cancellationEpisodes.firstIndex(where: { $0.id == loser.id }) else {
                continue
            }
            var stamped = loser
            stamped.deletedAt = monotonicStamp(instant, notBefore: stamped.createdAt)
            stamped.updatedAt = monotonicStamp(instant, notBefore: stamped.updatedAt)
            snapshot.cancellationEpisodes[index] = stamped
            counts.removed += 1
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
