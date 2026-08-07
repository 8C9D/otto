import Foundation
import OttoDomain

extension OttoSchemaV2.StoredPauseEpisode {
    private static let entityName = "StoredPauseEpisode"

    func toDomain() throws -> PauseEpisode {
        let entity = Self.entityName
        // Open or closed, never half (spec §5.3a) - refused loudly, before the
        // domain's construction precondition could trap on it.
        let domainOutcome: PauseEpisode.Outcome? = try outcome.map {
            try decodeRaw($0, entity: entity, field: "outcome")
        }
        let endedOn = try CalendarDay.storedOptional(endedOn, entity: entity, field: "endedOn")
        guard (endedOn == nil) == (domainOutcome == nil) else {
            throw MappingError.invalidValue(
                entity: entity,
                field: "endedOn/outcome",
                value: "\(endedOn.map(String.init(describing:)) ?? "nil")/\(domainOutcome?.rawValue ?? "nil")"
            )
        }
        return PauseEpisode(
            id: try require(id, entity: entity, field: "id"),
            // Nil means paused before Wave 7 recorded starts; Insights falls
            // back to the current price rather than inventing a freeze point.
            startedOn: try CalendarDay.storedOptional(startedOn, entity: entity, field: "startedOn"),
            scheduledResumeOn: try CalendarDay.storedOptional(
                scheduledResumeOn, entity: entity, field: "scheduledResumeOn"
            ),
            endedOn: endedOn,
            outcome: domainOutcome,
            createdAt: try require(createdAt, entity: entity, field: "createdAt"),
            updatedAt: try require(updatedAt, entity: entity, field: "updatedAt"),
            deletedAt: deletedAt
        )
    }

    func update(from domain: PauseEpisode) {
        id = domain.id
        startedOn = domain.startedOn?.yyyymmdd
        scheduledResumeOn = domain.scheduledResumeOn?.yyyymmdd
        endedOn = domain.endedOn?.yyyymmdd
        outcome = domain.outcome?.rawValue
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        deletedAt = domain.deletedAt
    }
}
