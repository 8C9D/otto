import Foundation
import OttoDomain

// Mapping between StoredSubscription (+ its embedded trial) and the domain
// Subscription. This file is where correctness lives: every nil-required-field and
// invalid-value case is decided here, explicitly, per the policy in MappingError.

extension OttoSchemaV1.StoredSubscription {
    private static let entityName = "StoredSubscription"

    func toDomain() throws -> Subscription {
        let entity = Self.entityName

        var domainTrial: TrialTerm?
        if let trial, trial.deletedAt == nil {
            domainTrial = try trial.toDomain()
        }

        // Spec §5.2b: a .trial subscription without a live trial term is an invariant
        // violation, refused here - loudly, before the domain's own construction
        // precondition could trip on it. Wave 3 had this state silently no-op'ing in
        // three separate places; now it cannot enter the domain at all.
        if status == SubscriptionStatus.trial.rawValue && domainTrial == nil {
            throw MappingError.missingField(entity: entity, field: "trial (required while status is .trial)")
        }

        return Subscription(
            id: try require(id, entity: entity, field: "id"),
            name: try require(name, entity: entity, field: "name"),
            vendorURL: try URL.storedOptional(vendorURL, entity: entity, field: "vendorURL"),
            category: try decodeRaw(category, entity: entity, field: "category"),
            status: try decodeRaw(status, entity: entity, field: "status"),
            amountCents: try require(amountCents, entity: entity, field: "amountCents"),
            currencyCode: try require(currencyCode, entity: entity, field: "currencyCode"),
            cycle: try BillingCycle.stored(unitRaw: cycleUnit, interval: cycleInterval, entity: entity),
            cycleStartDay: try CalendarDay.stored(cycleStartDay, entity: entity, field: "cycleStartDay"),
            reminderLeadDays: try require(reminderLeadDays, entity: entity, field: "reminderLeadDays"),
            sameDayReminder: sameDayReminder,
            pauseEndsOn: try CalendarDay.storedOptional(pauseEndsOn, entity: entity, field: "pauseEndsOn"),
            lastMaterializedThrough: try CalendarDay.storedOptional(
                lastMaterializedThrough, entity: entity, field: "lastMaterializedThrough"
            ),
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
    }

    /// Writes the domain value onto the record verbatim, syncing the trial child:
    /// a trial on the domain value reuses the existing record (clearing any
    /// tombstone - the one-to-one slot can only hold one record, so reuse is the
    /// only coherent choice); a trial absent from the domain value soft-deletes the
    /// record at the subscription's `updatedAt`, the caller-supplied instant of the
    /// change (no clock is read anywhere in the store).
    func update(from domain: Subscription) {
        id = domain.id
        name = domain.name
        vendorURL = domain.vendorURL?.absoluteString
        category = domain.category.rawValue
        status = domain.status.rawValue
        amountCents = domain.amountCents
        currencyCode = domain.currencyCode
        cycleUnit = domain.cycle.unit.rawValue
        cycleInterval = domain.cycle.interval
        cycleStartDay = domain.cycleStartDay.yyyymmdd
        reminderLeadDays = domain.reminderLeadDays
        sameDayReminder = domain.sameDayReminder
        pauseEndsOn = domain.pauseEndsOn?.yyyymmdd
        lastMaterializedThrough = domain.lastMaterializedThrough?.yyyymmdd
        paymentMethodID = domain.paymentMethodID
        cancellationURL = domain.cancellationURL?.absoluteString
        cancellationNotes = domain.cancellationNotes
        lastUsedDate = domain.lastUsedDate?.yyyymmdd
        notes = domain.notes
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt

        if let domainTrial = domain.trial {
            let record: OttoSchemaV1.StoredTrialTerm
            if let existing = trial {
                record = existing
            } else {
                record = OttoSchemaV1.StoredTrialTerm()
                trial = record
            }
            // Written verbatim, tombstone included: a live domain trial carries a nil
            // deletedAt, so reusing a tombstoned slot resurrects it.
            record.update(from: domainTrial)
        } else if let existing = trial, existing.deletedAt == nil {
            existing.deletedAt = domain.updatedAt
        }
    }
}

extension OttoSchemaV1.StoredTrialTerm {
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
