import Foundation
import SwiftData

extension OttoSchemaV2 {
    /// Persistence record for `PauseEpisode` (spec §5.3a) - one row per pause,
    /// reached through the one-to-many relationship, because pausing recurs.
    /// Like `StoredTrialTerm`, no scalar `subscriptionID`: the domain embeds
    /// pause episodes in their subscription and nothing fetches them alone.
    @Model
    final class StoredPauseEpisode {
        var id: UUID?
        /// yyyymmdd - the freeze point for §7.2's paused-spend price. Nil only
        /// on episodes migrated from records paused before Wave 7 recorded it.
        var startedOn: Int?
        /// yyyymmdd - when the vendor said billing resumes; nil is indefinite.
        var scheduledResumeOn: Int?
        /// yyyymmdd - when the pause actually ended; nil while current. The
        /// mapping enforces the pairing with `outcome` (spec §5.3a).
        var endedOn: Int?
        var outcome: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
