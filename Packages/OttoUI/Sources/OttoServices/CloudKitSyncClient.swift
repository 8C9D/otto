import CloudKit
import Foundation

/// The zone calls Otto makes itself. Everything else about CloudKit belongs to
/// the framework mirroring the store. A seam over `CKDatabase`, so the error
/// handling below is testable with no iCloud account.
protocol CloudKitZoneOperating: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    func fetchZone(_ id: CKRecordZone.ID) async throws
    func deleteZone(_ id: CKRecordZone.ID) async throws
}

/// The real `CloudSyncClient`.
///
/// `CKContainer` is created inside each call rather than held: constructing
/// one in a process without the iCloud entitlement raises an exception, and an
/// unsigned build must still launch. Nothing here runs unless the user asks.
public struct CloudKitSyncClient: CloudSyncClient {
    /// Where `NSPersistentCloudKitContainer` keeps a private store's records.
    /// Not public API, but stable since the framework shipped, and every
    /// mirrored record in the account is in it. Deleting it IS the purge;
    /// `docs/sync-verification.md` proves it against a real container.
    static let mirroredZoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName
    )

    private let operations: any CloudKitZoneOperating

    public init(containerIdentifier: String) {
        self.init(operations: LiveZoneOperations(containerIdentifier: containerIdentifier))
    }

    init(operations: any CloudKitZoneOperating) {
        self.operations = operations
    }

    public func accountStatus() async -> CloudAccountStatus {
        do {
            return Self.accountStatus(from: try await operations.accountStatus())
        } catch {
            OttoLog.sync.error("account status failed: \(Self.code(of: error), privacy: .public)")
            return .unknown
        }
    }

    static func accountStatus(from status: CKAccountStatus) -> CloudAccountStatus {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .unknown
        @unknown default: .unknown
        }
    }

    public func cloudCopyExists() async throws -> Bool {
        do {
            try await operations.fetchZone(Self.mirroredZoneID)
            return true
        } catch {
            if Self.isZoneMissing(error) { return false }
            throw Self.activationError(from: error)
        }
    }

    public func purgeZone() async throws {
        do {
            try await operations.deleteZone(Self.mirroredZoneID)
            OttoLog.sync.notice("zone purged")
        } catch {
            // Already gone is what was asked for. Idempotent on purpose: a
            // purge that succeeded but whose reply was lost must be retryable.
            if Self.isZoneMissing(error) { return }
            throw Self.activationError(from: error)
        }
    }

    static func isZoneMissing(_ error: any Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }
        return code == .zoneNotFound || code == .userDeletedZone
    }

    static func activationError(from error: any Error) -> any Error {
        guard let code = (error as? CKError)?.code else { return error }
        OttoLog.sync.error("cloud call failed: \(code.rawValue, privacy: .public)")
        switch code {
        case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted:
            return SyncActivationError.accountUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return SyncActivationError.cloudUnreachable
        default:
            return error
        }
    }

    private static func code(of error: any Error) -> Int {
        (error as NSError).code
    }
}

private struct LiveZoneOperations: CloudKitZoneOperating {
    let containerIdentifier: String

    private var database: CKDatabase {
        CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await CKContainer(identifier: containerIdentifier).accountStatus()
    }

    func fetchZone(_ id: CKRecordZone.ID) async throws {
        _ = try await database.recordZone(for: id)
    }

    func deleteZone(_ id: CKRecordZone.ID) async throws {
        try await database.deleteRecordZone(withID: id)
    }
}
