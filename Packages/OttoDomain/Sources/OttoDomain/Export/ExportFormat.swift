import Foundation

// The export wire format (spec §3.5: export/import is a first-class v1 feature,
// and after Wave 6 it is the only path out of CloudKit). These types are the
// format: they mirror the domain models field for field TODAY, but they are
// deliberately separate declarations, because coupling the wire format to
// either the persistence schema or the domain structs means every future
// migration silently breaks the old export files - exactly the files a
// migration needs most.
//
// Format conventions, frozen in v1:
// - calendar days are "YYYY-MM-DD" strings
// - instants are JSON numbers of seconds since 2001-01-01T00:00:00Z (Swift's
//   `Date` reference encoding, kept because it round-trips bit-exactly)
// - money is integer cents, never floating point and never formatted strings
// - enums are the lower-camel-case strings pinned by `WireFormatTests`
// - the device-local materialization watermark is ABSENT by design (spec §5.3):
//   it describes this device's ledger progress, not the user's data
//
// Format v2 (Wave 8.5, spec §5.3a §3.5): the version policy is that ANY field
// change bumps the version, additive included, because Codable silently drops
// unknown keys - a newer export restoring into an older app would lose data
// with no error anywhere, which is this application's forbidden failure mode.
// v2's changes:
// - subscriptions carry `pauseEpisodes` (a history array); v1's single
//   `pausedOn`/`pauseEndsOn` pair is no longer written
// - the top-level array is `cancellationEpisodes` (one-to-many, each with
//   `statusAtStart`, `endedAt` and `outcome`); v1's `cancellationRecords` key
//   is no longer written
//
// Reading a v1 file remains supported, with these documented defaults:
// - a subscription's pause fields become ONE open pause episode (started on
//   `pausedOn`, scheduled to resume on `pauseEndsOn`), with an id DERIVED from
//   the subscription id so re-importing the same file cannot duplicate it, and
//   timestamps borrowed from the subscription (the closest instant v1 recorded)
// - each cancellation record becomes an episode with `statusAtStart` absent
//   (v1 never captured it); a `verifiedStopped` record closes at its
//   verification instant, every other state stays open
//   (`CancellationEpisode.legacyClosure` - one rule with the SwiftData
//   migration)

/// A whole database as the export format describes it.
public struct OttoExport: Hashable, Sendable {
    public static let currentFormatVersion = 2

    /// The version THE FILE declared - 1 for an upgraded legacy file. Encoding
    /// a fresh export always writes `currentFormatVersion`.
    public let formatVersion: Int
    public let exportedAt: Date
    public var subscriptions: [ExportedSubscription]
    public var paymentMethods: [ExportedPaymentMethod]
    public var billingEvents: [ExportedBillingEvent]
    public var cancellationEpisodes: [ExportedCancellationEpisode]
    public var priceChanges: [ExportedPriceChange]

    /// Deterministic order (by id) so identical databases export identical bytes.
    public init(snapshot: OttoDataSnapshot, exportedAt: Date) {
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.subscriptions = snapshot.subscriptions
            .map(ExportedSubscription.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        self.paymentMethods = snapshot.paymentMethods
            .map(ExportedPaymentMethod.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        self.billingEvents = snapshot.billingEvents
            .map(ExportedBillingEvent.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        self.cancellationEpisodes = snapshot.cancellationEpisodes
            .map(ExportedCancellationEpisode.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        self.priceChanges = snapshot.priceChanges
            .map(ExportedPriceChange.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// The domain values the file describes. Every invariant the domain enforces
    /// with a precondition is checked HERE with a thrown error first, because a
    /// malformed file must fail the import cleanly (spec Wave 8: atomic, never a
    /// crash and never a half-restore).
    public func snapshot() throws -> OttoDataSnapshot {
        OttoDataSnapshot(
            subscriptions: try subscriptions.map { try $0.domainValue() },
            paymentMethods: try paymentMethods.map { try $0.domainValue() },
            billingEvents: try billingEvents.map { try $0.domainValue() },
            cancellationEpisodes: try cancellationEpisodes.map { try $0.domainValue() },
            priceChanges: try priceChanges.map { try $0.domainValue() }
        )
    }

    /// A v1 file, read with v2's documented defaults (see the header). Called
    /// exactly once, by `decodeExport` when the probe said 1 - never on v2
    /// data, whose episodes must round-trip verbatim.
    func upgradedFromV1() -> OttoExport {
        var upgraded = self
        upgraded.subscriptions = subscriptions.map { $0.upgradedFromV1() }
        upgraded.cancellationEpisodes = cancellationEpisodes.map { $0.upgradedFromV1() }
        return upgraded
    }
}

// MARK: - Codable

extension OttoExport: Codable {
    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, subscriptions, paymentMethods, billingEvents
        case cancellationEpisodes
        /// v1's name for the same array - read, never written.
        case legacyCancellationRecords = "cancellationRecords"
        case priceChanges
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        subscriptions = try container.decode([ExportedSubscription].self, forKey: .subscriptions)
        paymentMethods = try container.decode([ExportedPaymentMethod].self, forKey: .paymentMethods)
        billingEvents = try container.decode([ExportedBillingEvent].self, forKey: .billingEvents)
        cancellationEpisodes = try container.decodeIfPresent(
            [ExportedCancellationEpisode].self, forKey: .cancellationEpisodes
        ) ?? container.decode(
            [ExportedCancellationEpisode].self, forKey: .legacyCancellationRecords
        )
        priceChanges = try container.decode([ExportedPriceChange].self, forKey: .priceChanges)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(subscriptions, forKey: .subscriptions)
        try container.encode(paymentMethods, forKey: .paymentMethods)
        try container.encode(billingEvents, forKey: .billingEvents)
        try container.encode(cancellationEpisodes, forKey: .cancellationEpisodes)
        try container.encode(priceChanges, forKey: .priceChanges)
    }
}

// MARK: - Wire records

public struct ExportedSubscription: Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var vendorURL: String?
    public var category: String
    public var status: String
    public var amountCents: Int
    public var currencyCode: String
    public var cycleUnit: String
    public var cycleInterval: Int
    public var cycleStartDay: String
    public var reminderLeadDays: Int
    public var sameDayReminder: Bool
    public var pauseEpisodes: [ExportedPauseEpisode]
    /// v1's single pause pair - read for the upgrade, never written.
    var legacyPausedOn: String?
    var legacyPauseEndsOn: String?
    public var trial: ExportedTrialTerm?
    public var paymentMethodID: UUID?
    public var cancellationURL: String?
    public var cancellationNotes: String?
    public var lastUsedDate: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: Subscription) {
        id = domain.id
        name = domain.name
        vendorURL = domain.vendorURL?.absoluteString
        category = domain.category.rawValue
        status = domain.storedStatus.rawValue
        amountCents = domain.amountCents
        currencyCode = domain.currencyCode
        cycleUnit = domain.cycle.unit.rawValue
        cycleInterval = domain.cycle.interval
        cycleStartDay = domain.cycleStartDay.description
        reminderLeadDays = domain.reminderLeadDays
        sameDayReminder = domain.sameDayReminder
        pauseEpisodes = domain.pauseEpisodes.map(ExportedPauseEpisode.init)
        legacyPausedOn = nil
        legacyPauseEndsOn = nil
        trial = domain.trial.map(ExportedTrialTerm.init)
        paymentMethodID = domain.paymentMethodID
        cancellationURL = domain.cancellationURL?.absoluteString
        cancellationNotes = domain.cancellationNotes
        lastUsedDate = domain.lastUsedDate?.description
        notes = domain.notes
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> Subscription {
        let entity = "subscription \(id)"
        let status: SubscriptionStatus = try wireEnum(self.status, entity: entity, field: "status")
        let trial = try trial.map { try $0.domainValue() }
        // The §5.2b invariant, thrown instead of the domain's precondition.
        guard status != .trial || trial != nil else {
            throw ExportFormatError.invalidValue(
                entity: entity, field: "trial", value: "absent while status is trial"
            )
        }
        guard let unit = BillingCycle.Unit(rawValue: cycleUnit),
              let cycle = BillingCycle(unit: unit, interval: cycleInterval)
        else {
            throw ExportFormatError.invalidValue(
                entity: entity, field: "cycle", value: "\(cycleUnit)/\(cycleInterval)"
            )
        }
        // The §5.3a invariants, thrown instead of the domain's preconditions.
        let episodes = try pauseEpisodes.map { try $0.domainValue() }
        try Subscription.checkPauseInvariants(status: status, pauseEpisodes: episodes) {
            ExportFormatError.invalidValue(entity: entity, field: "pauseEpisodes", value: $0)
        }
        return Subscription(
            id: id,
            name: name,
            vendorURL: try wireURL(vendorURL, entity: entity, field: "vendorURL"),
            category: try wireEnum(category, entity: entity, field: "category"),
            status: status,
            amountCents: amountCents,
            currencyCode: currencyCode,
            cycle: cycle,
            cycleStartDay: try wireDay(cycleStartDay, entity: entity, field: "cycleStartDay"),
            reminderLeadDays: reminderLeadDays,
            sameDayReminder: sameDayReminder,
            pauseEpisodes: episodes,
            // Absent from the file by design; the importing device's ledger
            // starts observing from its own today (spec §5.3).
            lastMaterializedThrough: nil,
            trial: trial,
            paymentMethodID: paymentMethodID,
            cancellationURL: try wireURL(cancellationURL, entity: entity, field: "cancellationURL"),
            cancellationNotes: cancellationNotes,
            lastUsedDate: try wireDay(lastUsedDate, entity: entity, field: "lastUsedDate"),
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    /// The v1 upgrade (documented in the file header): the single pause pair
    /// becomes one OPEN episode, with a derived id and borrowed timestamps.
    func upgradedFromV1() -> ExportedSubscription {
        var upgraded = self
        upgraded.legacyPausedOn = nil
        upgraded.legacyPauseEndsOn = nil
        guard pauseEpisodes.isEmpty,
              PauseEpisode.legacyEpisodeExists(
                  statusRaw: status,
                  hasStart: legacyPausedOn != nil,
                  hasScheduledResume: legacyPauseEndsOn != nil
              )
        else { return upgraded }
        upgraded.pauseEpisodes = [ExportedPauseEpisode(
            id: legacyPauseEpisodeID(for: id),
            startedOn: legacyPausedOn,
            scheduledResumeOn: legacyPauseEndsOn,
            endedOn: nil,
            outcome: nil,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            deletedAt: nil
        )]
        return upgraded
    }
}

extension ExportedSubscription: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, vendorURL, category, status, amountCents, currencyCode
        case cycleUnit, cycleInterval, cycleStartDay, reminderLeadDays, sameDayReminder
        case pauseEpisodes
        case legacyPausedOn = "pausedOn"
        case legacyPauseEndsOn = "pauseEndsOn"
        case trial, paymentMethodID, cancellationURL, cancellationNotes
        case lastUsedDate, notes, createdAt, updatedAt, deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        vendorURL = try container.decodeIfPresent(String.self, forKey: .vendorURL)
        category = try container.decode(String.self, forKey: .category)
        status = try container.decode(String.self, forKey: .status)
        amountCents = try container.decode(Int.self, forKey: .amountCents)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        cycleUnit = try container.decode(String.self, forKey: .cycleUnit)
        cycleInterval = try container.decode(Int.self, forKey: .cycleInterval)
        cycleStartDay = try container.decode(String.self, forKey: .cycleStartDay)
        reminderLeadDays = try container.decode(Int.self, forKey: .reminderLeadDays)
        sameDayReminder = try container.decode(Bool.self, forKey: .sameDayReminder)
        pauseEpisodes = try container.decodeIfPresent([ExportedPauseEpisode].self, forKey: .pauseEpisodes) ?? []
        legacyPausedOn = try container.decodeIfPresent(String.self, forKey: .legacyPausedOn)
        legacyPauseEndsOn = try container.decodeIfPresent(String.self, forKey: .legacyPauseEndsOn)
        trial = try container.decodeIfPresent(ExportedTrialTerm.self, forKey: .trial)
        paymentMethodID = try container.decodeIfPresent(UUID.self, forKey: .paymentMethodID)
        cancellationURL = try container.decodeIfPresent(String.self, forKey: .cancellationURL)
        cancellationNotes = try container.decodeIfPresent(String.self, forKey: .cancellationNotes)
        lastUsedDate = try container.decodeIfPresent(String.self, forKey: .lastUsedDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(vendorURL, forKey: .vendorURL)
        try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status)
        try container.encode(amountCents, forKey: .amountCents)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(cycleUnit, forKey: .cycleUnit)
        try container.encode(cycleInterval, forKey: .cycleInterval)
        try container.encode(cycleStartDay, forKey: .cycleStartDay)
        try container.encode(reminderLeadDays, forKey: .reminderLeadDays)
        try container.encode(sameDayReminder, forKey: .sameDayReminder)
        try container.encode(pauseEpisodes, forKey: .pauseEpisodes)
        // The legacy pause pair is never written: v2 files carry episodes only.
        try container.encodeIfPresent(trial, forKey: .trial)
        try container.encodeIfPresent(paymentMethodID, forKey: .paymentMethodID)
        try container.encodeIfPresent(cancellationURL, forKey: .cancellationURL)
        try container.encodeIfPresent(cancellationNotes, forKey: .cancellationNotes)
        try container.encodeIfPresent(lastUsedDate, forKey: .lastUsedDate)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}
