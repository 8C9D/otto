import Foundation

// The export wire format (spec §3.5: export/import is a first-class v1 feature,
// and after Wave 6 it is the only path out of CloudKit). These types are the
// format: they mirror the domain models field for field TODAY, but they are
// deliberately separate declarations, because coupling the wire format to
// either the persistence schema or the domain structs means every future
// migration silently breaks the old export files - exactly the files a
// migration needs most.
//
// Format v1 conventions, frozen:
// - calendar days are "YYYY-MM-DD" strings
// - instants are JSON numbers of seconds since 2001-01-01T00:00:00Z (Swift's
//   `Date` reference encoding, kept because it round-trips bit-exactly)
// - money is integer cents, never floating point and never formatted strings
// - enums are the lower-camel-case strings pinned by `WireFormatTests`
// - the device-local materialization watermark is ABSENT by design (spec §5.3):
//   it describes this device's ledger progress, not the user's data

/// A whole database as format v1 describes it.
public struct OttoExport: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public var subscriptions: [ExportedSubscription]
    public var paymentMethods: [ExportedPaymentMethod]
    public var billingEvents: [ExportedBillingEvent]
    public var cancellationRecords: [ExportedCancellationRecord]
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
        self.cancellationRecords = snapshot.cancellationRecords
            .map(ExportedCancellationRecord.init)
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
            cancellationRecords: try cancellationRecords.map { try $0.domainValue() },
            priceChanges: try priceChanges.map { try $0.domainValue() }
        )
    }
}

// MARK: - Wire records

public struct ExportedSubscription: Codable, Hashable, Sendable {
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
    public var pauseEndsOn: String?
    public var pausedOn: String?
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
        pauseEndsOn = domain.pauseEndsOn?.description
        pausedOn = domain.pausedOn?.description
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
            pauseEndsOn: try wireDay(pauseEndsOn, entity: entity, field: "pauseEndsOn"),
            pausedOn: try wireDay(pausedOn, entity: entity, field: "pausedOn"),
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
}

public struct ExportedTrialTerm: Codable, Hashable, Sendable {
    public let id: UUID
    public var startDate: String
    public var lengthDays: Int
    public var bufferDays: Int
    public var convertsToAmountCents: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(_ domain: TrialTerm) {
        id = domain.id
        startDate = domain.startDate.description
        lengthDays = domain.lengthDays
        bufferDays = domain.bufferDays
        convertsToAmountCents = domain.convertsToAmountCents
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }

    public func domainValue() throws -> TrialTerm {
        let entity = "trial \(id)"
        guard let term = TrialTerm(
            id: id,
            startDate: try wireDay(startDate, entity: entity, field: "startDate"),
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        ) else {
            throw ExportFormatError.invalidValue(
                entity: entity,
                field: "lengthDays/bufferDays/convertsToAmountCents",
                value: "\(lengthDays)/\(bufferDays)/\(convertsToAmountCents)"
            )
        }
        return term
    }
}
