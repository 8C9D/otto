import Foundation
import OttoDomain

// Mapping between StoredSubscription (+ its embedded trial and pause episodes)
// and the domain Subscription. This file is where correctness lives: every
// nil-required-field and invalid-value case is decided here, explicitly, per
// the policy in MappingError.

extension OttoSchemaV3.StoredSubscription {
    private static let entityName = "StoredSubscription"

    func toDomain() throws -> Subscription {
        var repairs: [SubscriptionReadRepair] = []
        return try toDomain(collecting: &repairs)
    }

    /// The §4a repairing read (v2.0): shapes two correct devices can produce
    /// between them - two open pause episodes, an episode racing a status, a
    /// parent arriving before its trial or episode child - are repaired or
    /// held deterministically instead of refused, and reported to `repairs`
    /// for the aggregate needs-review surface. Field-level damage (a missing
    /// required column, an unknown enum) still throws: there is no honest
    /// repair for a value that does not exist.
    func toDomain(collecting repairs: inout [SubscriptionReadRepair]) throws -> Subscription {
        let entity = Self.entityName

        var domainTrial: TrialTerm?
        if let trial, trial.deletedAt == nil {
            domainTrial = try trial.toDomain()
        }

        // Tombstoned episodes ride along: they are communicable history
        // (spec §3.5) and the export snapshot reads through this same mapping.
        // Deterministic order so identical stores map to identical values.
        let domainStatus: SubscriptionStatus = try decodeRaw(status, entity: entity, field: "status")
        let episodes = try (pauseEpisodes ?? [])
            .map { try $0.toDomain() }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }

        let repaired = Subscription.readingRepaired(
            id: try require(id, entity: entity, field: "id"),
            name: try require(name, entity: entity, field: "name"),
            vendorURL: try URL.storedOptional(vendorURL, entity: entity, field: "vendorURL"),
            category: try decodeRaw(category, entity: entity, field: "category"),
            status: domainStatus,
            amountCents: try require(amountCents, entity: entity, field: "amountCents"),
            currencyCode: try require(currencyCode, entity: entity, field: "currencyCode"),
            cycle: try BillingCycle.stored(unitRaw: cycleUnit, interval: cycleInterval, entity: entity),
            cycleStartDay: try CalendarDay.stored(cycleStartDay, entity: entity, field: "cycleStartDay"),
            reminderLeadDays: try require(reminderLeadDays, entity: entity, field: "reminderLeadDays"),
            sameDayReminder: sameDayReminder,
            pauseEpisodes: episodes,
            trial: domainTrial,
            paymentMethodID: paymentMethodID,
            cancellationURL: try URL.storedOptional(cancellationURL, entity: entity, field: "cancellationURL"),
            cancellationNotes: cancellationNotes,
            lastUsedDate: try CalendarDay.storedOptional(lastUsedDate, entity: entity, field: "lastUsedDate"),
            notes: notes,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
        repairs.append(contentsOf: repaired.repairs)
        return repaired.subscription
    }

    /// Writes the domain value onto the record verbatim, applying its children
    /// to identified records: a trial on the domain value reuses the existing
    /// record (clearing any tombstone - the one-to-one slot can only hold one
    /// record, so reuse is the only coherent choice), and each pause episode
    /// updates the record carrying its id or inserts a new one.
    ///
    /// **Absence is not deletion** (spec §4a, Wave 6B-Prep): a stored child the
    /// domain value does not carry is left exactly as it is. Under per-record
    /// sync a stale in-memory snapshot is ordinary, and the old contract -
    /// "absence is deliberate removal" - silently tombstoned records the
    /// snapshot had simply never seen. Deletion is expressed only as an
    /// explicit operation on an identified record: a domain child carrying its
    /// tombstone, or the delete cascade. This save path cannot remove anything.
    func update(from domain: Subscription) {
        id = domain.id
        name = domain.name
        vendorURL = domain.vendorURL?.absoluteString
        category = domain.category.rawValue
        status = domain.storedStatus.rawValue
        amountCents = domain.amountCents
        currencyCode = domain.currencyCode
        cycleUnit = domain.cycle.unit.rawValue
        cycleInterval = domain.cycle.interval
        cycleStartDay = domain.cycleStartDay.yyyymmdd
        reminderLeadDays = domain.reminderLeadDays
        sameDayReminder = domain.sameDayReminder
        paymentMethodID = domain.paymentMethodID
        cancellationURL = domain.cancellationURL?.absoluteString
        cancellationNotes = domain.cancellationNotes
        lastUsedDate = domain.lastUsedDate?.yyyymmdd
        notes = domain.notes
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt

        if let domainTrial = domain.trial {
            let record: OttoSchemaV3.StoredTrialTerm
            if let existing = trial {
                record = existing
            } else {
                record = OttoSchemaV3.StoredTrialTerm()
                trial = record
            }
            // Written verbatim, tombstone included: a live domain trial carries a nil
            // deletedAt, so reusing a tombstoned slot resurrects it - and removing
            // the trial is a domain value carrying the term WITH its tombstone
            // (`editedTrial`), never an absent slot.
            record.update(from: domainTrial)
        }

        upsertPauseEpisodes(from: domain)
    }

    private func upsertPauseEpisodes(from domain: Subscription) {
        let storedByID = Dictionary(
            (pauseEpisodes ?? []).compactMap { record in record.id.map { ($0, record) } },
            uniquingKeysWith: { first, _ in first }
        )
        for episode in domain.pauseEpisodes {
            if let existing = storedByID[episode.id] {
                existing.update(from: episode)
            } else {
                let record = OttoSchemaV3.StoredPauseEpisode()
                record.subscription = self
                record.update(from: episode)
            }
        }
    }
}

extension OttoSchemaV3.StoredTrialTerm {
    private static let entityName = "StoredTrialTerm"

    func toDomain() throws -> TrialTerm {
        let entity = Self.entityName
        let startDate = try CalendarDay.stored(startDate, entity: entity, field: "startDate")
        let lengthDays = try require(lengthDays, entity: entity, field: "lengthDays")
        let bufferDays = try require(bufferDays, entity: entity, field: "bufferDays")
        let convertsTo = try require(convertsToAmountCents, entity: entity, field: "convertsToAmountCents")
        guard let term = TrialTerm(
            id: try require(id, entity: entity, field: "id"),
            startDate: startDate,
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsTo,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        ) else {
            throw MappingError.invalidValue(
                entity: entity,
                field: "lengthDays/bufferDays/convertsToAmountCents",
                value: "\(lengthDays)/\(bufferDays)/\(convertsTo)"
            )
        }
        return term
    }

    func update(from domain: TrialTerm) {
        id = domain.id
        startDate = domain.startDate.yyyymmdd
        lengthDays = domain.lengthDays
        bufferDays = domain.bufferDays
        convertsToAmountCents = domain.convertsToAmountCents
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
