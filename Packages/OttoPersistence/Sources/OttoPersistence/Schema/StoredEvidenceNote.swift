import Foundation
import SwiftData

extension OttoSchemaV3 {
    /// Persistence record for `EvidenceNote` (spec §5.4, a list since v1.9) -
    /// one row per dispute artifact, reached through the one-to-many
    /// relationship, because a long cancellation fight produces many. Like
    /// `StoredPauseEpisode`, no scalar episode id: the domain embeds notes in
    /// their episode and nothing fetches them alone.
    @Model
    final class StoredEvidenceNote {
        var id: UUID?
        var text: String?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var episode: StoredCancellationEpisode?

        init() {}
    }
}
