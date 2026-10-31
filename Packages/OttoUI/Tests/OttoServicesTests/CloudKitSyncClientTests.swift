import CloudKit
import Foundation
import Testing
@testable import OttoServices

/// Scripts `CKDatabase`'s answers. A real one needs a signed build and an
/// iCloud account, so what these cover is what Otto does with the answers;
/// whether the calls are right is `docs/sync-verification.md`'s job.
private struct ScriptedZoneOperations: CloudKitZoneOperating {
    var account: Result<CKAccountStatus, CKError> = .success(.available)
    var fetch: Result<Void, CKError> = .success(())
    var delete: Result<Void, CKError> = .success(())

    func accountStatus() async throws -> CKAccountStatus { try account.get() }
    func fetchZone(_ id: CKRecordZone.ID) async throws { try fetch.get() }
    func deleteZone(_ id: CKRecordZone.ID) async throws { try delete.get() }
}

@Suite("The CloudKit client (spec §8, Wave 6B)")
struct CloudKitSyncClientTests {

    @Test("account statuses map one to one", arguments: [
        (CKAccountStatus.available, CloudAccountStatus.available),
        (.noAccount, .noAccount),
        (.restricted, .restricted),
        (.temporarilyUnavailable, .temporarilyUnavailable),
        (.couldNotDetermine, .unknown)
    ])
    func accountStatusMaps(status: CKAccountStatus, expected: CloudAccountStatus) async {
        let client = CloudKitSyncClient(operations: ScriptedZoneOperations(account: .success(status)))
        #expect(await client.accountStatus() == expected)
    }

    @Test("a failed account check reports unknown, which the enable flow refuses")
    func accountFailureIsUnknown() async {
        let client = CloudKitSyncClient(
            operations: ScriptedZoneOperations(account: .failure(CKError(.networkFailure)))
        )
        #expect(await client.accountStatus() == .unknown)
    }

    @Test("a zone that answers is a cloud copy")
    func zonePresent() async throws {
        #expect(try await CloudKitSyncClient(operations: ScriptedZoneOperations()).cloudCopyExists())
    }

    @Test("a missing zone means no cloud copy", arguments: [CKError.Code.zoneNotFound, .userDeletedZone])
    func zoneMissing(code: CKError.Code) async throws {
        let client = CloudKitSyncClient(operations: ScriptedZoneOperations(fetch: .failure(CKError(code))))
        #expect(try await client.cloudCopyExists() == false)
    }

    @Test("an unanswerable zone check throws: it is never read as 'no copy'", arguments: [
        (CKError.Code.networkUnavailable, SyncActivationError.cloudUnreachable),
        (.networkFailure, .cloudUnreachable),
        (.serviceUnavailable, .cloudUnreachable),
        (.requestRateLimited, .cloudUnreachable),
        (.notAuthenticated, .accountUnavailable)
    ])
    func zoneCheckFailures(code: CKError.Code, expected: SyncActivationError) async {
        let client = CloudKitSyncClient(operations: ScriptedZoneOperations(fetch: .failure(CKError(code))))
        await #expect(throws: expected) {
            _ = try await client.cloudCopyExists()
        }
    }

    @Test("an error with no mapping surfaces as itself, not as a clear cloud")
    func unmappedFailureSurfaces() async {
        let client = CloudKitSyncClient(operations: ScriptedZoneOperations(fetch: .failure(CKError(.internalError))))
        await #expect(throws: CKError.self) {
            _ = try await client.cloudCopyExists()
        }
    }

    @Test("purging an already-missing zone succeeds, so a lost reply can be retried")
    func purgeIsIdempotent() async throws {
        let client = CloudKitSyncClient(operations: ScriptedZoneOperations(delete: .failure(CKError(.zoneNotFound))))
        try await client.purgeZone()
    }

    @Test("a purge that could not run is reported")
    func purgeFailureSurfaces() async {
        let client = CloudKitSyncClient(operations: ScriptedZoneOperations(delete: .failure(CKError(.networkFailure))))
        await #expect(throws: SyncActivationError.cloudUnreachable) {
            try await client.purgeZone()
        }
    }

    @Test("the purge targets the zone mirroring writes to, in the user's own database")
    func mirroredZoneIdentity() {
        #expect(CloudKitSyncClient.mirroredZoneID.zoneName == "com.apple.coredata.cloudkit.zone")
        #expect(CloudKitSyncClient.mirroredZoneID.ownerName == CKCurrentUserDefaultName)
    }
}
