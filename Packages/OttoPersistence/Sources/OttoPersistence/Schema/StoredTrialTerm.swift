import Foundation
import SwiftData

extension OttoSchemaV3 {
    /// Persistence record for `TrialTerm` (spec §5.2). The domain embeds the trial
    /// in its subscription; here it is a separate record reached through the
    /// one-to-one relationship, which is what CloudKit can sync.
    @Model
    final class StoredTrialTerm {
        var id: UUID?
        /// yyyymmdd
        var startDate: Int?
        var lengthDays: Int?
        var bufferDays: Int?
        var convertsToAmountCents: Int?
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        var subscription: StoredSubscription?

        init() {}
    }
}
