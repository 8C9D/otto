import Foundation

/// Failures a repository can report beyond what the storage framework throws.
public enum RepositoryError: Error, Equatable, Sendable {
    /// A child record (billing event, cancellation record, price change) was saved
    /// for a subscription that has no persisted record.
    case subscriptionNotFound(UUID)
    case paymentMethodNotFound(UUID)
    /// A restore was requested while sync could still run (spec §8, v2.1).
    /// Restoring into a live mirror lets other devices' edits land on the
    /// restored rows mid-restore, and "engage the kill switch first" as a
    /// remembered rule is exactly the kind that fails during an incident -
    /// this project's history is documentation failing where structure holds,
    /// so `restore()` refuses structurally instead.
    case restoreRequiresSyncDisengaged
}

extension RepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .restoreRequiresSyncDisengaged:
            return String(
                localized: """
                Sync is still on. Turn on the sync kill switch in Settings and \
                relaunch the app, then run the restore again.
                """,
                comment: "Shown when a restore or import is refused because sync has not been disengaged"
            )
        case .subscriptionNotFound, .paymentMethodNotFound:
            return nil
        }
    }
}
