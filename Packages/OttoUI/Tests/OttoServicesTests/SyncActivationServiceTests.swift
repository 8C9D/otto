import Foundation
import Testing
import OttoDomain
import OttoRepositories
@testable import OttoServices

/// A transfer seam that can be primed to fail, for proving the enable flow's
/// ordering: no snapshot on disk, no sync flag.
private actor SnapshotTransfer: DataTransferRepository {
    private let snapshot: OttoDataSnapshot
    private let failure: (any Error)?

    init(snapshot: OttoDataSnapshot = OttoDataSnapshot(), failure: (any Error)? = nil) {
        self.snapshot = snapshot
        self.failure = failure
    }

    func completeSnapshot() async throws -> OttoDataSnapshot {
        if let failure { throw failure }
        return snapshot
    }

    func restore(
        _ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy
    ) async throws {}
    func reconstructMaterializationWatermarks() async throws {}
}

/// A scriptable iCloud: an available account and an empty cloud unless a test
/// says otherwise, recording what was asked of it.
private actor FakeCloud: CloudSyncClient {
    private(set) var purgeCalls = 0
    private(set) var copyChecks = 0
    private let account: CloudAccountStatus
    private let copyExists: Result<Bool, SyncActivationError>

    init(account: CloudAccountStatus = .available, copyExists: Result<Bool, SyncActivationError> = .success(false)) {
        self.account = account
        self.copyExists = copyExists
    }

    func accountStatus() async -> CloudAccountStatus { account }

    func cloudCopyExists() async throws -> Bool {
        copyChecks += 1
        return try copyExists.get()
    }

    func purgeZone() async throws {
        purgeCalls += 1
    }
}

private struct TransferFailure: Error {}

// Spec §8 (Wave 6B-Prep): the enable/disable machinery, tested while there is
// nothing to lose - the only time it can be tested honestly.
//
// `UserDefaults` is not Sendable, so every use opens its own instance over the
// same suite; the suite name is the shared state.
@Suite("Sync activation (spec §8)", .serialized)
struct SyncActivationServiceTests {

    private func resetSuite(_ name: String) throws {
        try #require(UserDefaults(suiteName: name)).removePersistentDomain(forName: name)
    }

    private func loadState(_ name: String) throws -> SyncState {
        SyncState.load(from: try #require(UserDefaults(suiteName: name)))
    }

    private func makeService(
        suite: String,
        transfer: any DataTransferRepository,
        cloud: any CloudSyncClient = FakeCloud(),
        sessionMode: SyncSessionMode = .off
    ) throws -> SyncActivationService {
        SyncActivationService(
            transfer: transfer,
            userDefaults: try #require(UserDefaults(suiteName: suite)),
            snapshotDirectory: try scratchDirectory(),
            cloud: cloud,
            sessionMode: sessionMode
        )
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-activation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("enabling sync writes the pre-enable snapshot BEFORE the flag flips")
    func enableTakesSnapshotFirst() async throws {
        let suite = "sync-activation-enable"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        let service = try makeService(
            suite: suite,
            transfer: SnapshotTransfer(snapshot: OttoDataSnapshot(subscriptions: [subscription]))
        )

        let url = try await service.enableSync(
            exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
        )

        #expect(url.lastPathComponent == "Otto-PreSync-Backup-2026-08-07.json")
        // The snapshot is a real, decodable export - the rollback point.
        let written = try importedSnapshot(from: try Data(contentsOf: url))
        #expect(written.subscriptions.map(\.id) == [subscription.id])
        #expect(try loadState(suite).isEnabled)
    }

    @Test("a failed snapshot means sync stays OFF - the flag never flips without the file")
    func failedSnapshotLeavesSyncOff() async throws {
        let suite = "sync-activation-failure"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let service = try makeService(suite: suite, transfer: SnapshotTransfer(failure: TransferFailure()))

        await #expect(throws: TransferFailure.self) {
            try await service.enableSync(
                exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
            )
        }
        #expect(try loadState(suite) == SyncState())
    }

    @Test("an engaged kill switch blocks enabling - releasing the brake is its own deliberate act")
    func killSwitchBlocksEnable() async throws {
        let suite = "sync-activation-killswitch"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let service = try makeService(suite: suite, transfer: SnapshotTransfer())
        await service.engageKillSwitch()

        await #expect(throws: SyncActivationError.killSwitchEngaged) {
            try await service.enableSync(
                exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
            )
        }
        #expect(try loadState(suite).isEnabled == false)
    }

    @Test("the zone purge refuses while sync could still run, and purges once the kill switch is engaged")
    func zonePurgeRequiresKillSwitch() async throws {
        let suite = "sync-activation-purge"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let cloud = FakeCloud()
        let service = try makeService(suite: suite, transfer: SnapshotTransfer(), cloud: cloud)

        await #expect(throws: SyncActivationError.killSwitchNotEngaged) {
            try await service.purgeCloudZone()
        }
        #expect(await cloud.purgeCalls == 0)

        await service.engageKillSwitch()
        try await service.purgeCloudZone()
        #expect(await cloud.purgeCalls == 1)
    }

    @Test("the purge refuses in a session that opened mirrored: the brake acts at the next launch")
    func zonePurgeRefusesWhileStillMirroring() async throws {
        let suite = "sync-activation-purge-mirrored"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let cloud = FakeCloud()
        let service = try makeService(
            suite: suite, transfer: SnapshotTransfer(), cloud: cloud, sessionMode: .mirrored
        )
        await service.engageKillSwitch()

        // The live store would recreate the zone it was just told to forget.
        await #expect(throws: SyncActivationError.killSwitchNotYetInEffect) {
            try await service.purgeCloudZone()
        }
        #expect(await cloud.purgeCalls == 0)
    }

    @Test("a successful purge leaves this device plain off, so turning sync on again takes a fresh snapshot")
    func purgeReturnsToOff() async throws {
        let suite = "sync-activation-purge-off"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        SyncState.setEnabled(true, in: defaults)
        let service = try makeService(suite: suite, transfer: SnapshotTransfer())
        await service.engageKillSwitch()

        try await service.purgeCloudZone()

        #expect(try loadState(suite) == SyncState())
    }

    @Test("the default client refuses loudly instead of pretending")
    func defaultClientRefuses() async throws {
        let client = UnavailableCloudSyncClient()
        await #expect(throws: SyncActivationError.cloudUnavailable) { try await client.purgeZone() }
        await #expect(throws: SyncActivationError.cloudUnavailable) { _ = try await client.cloudCopyExists() }
        #expect(await client.accountStatus() == .unknown)
    }

    @Test("no usable iCloud account means no snapshot and no flag", arguments: [
        CloudAccountStatus.noAccount, .restricted, .temporarilyUnavailable, .unknown
    ])
    func enableRequiresAnAccount(status: CloudAccountStatus) async throws {
        let suite = "sync-activation-account"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let directory = try scratchDirectory()
        let service = SyncActivationService(
            transfer: SnapshotTransfer(),
            userDefaults: try #require(UserDefaults(suiteName: suite)),
            snapshotDirectory: directory,
            cloud: FakeCloud(account: status)
        )

        await #expect(throws: SyncActivationError.accountUnavailable) {
            try await service.enableSync(
                exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
            )
        }
        #expect(try loadState(suite) == SyncState())
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    /// The reinstall-then-import path: a backup restored here carries the same
    /// ids as the records already in iCloud, and CloudKit would keep both.
    @Test("a device with records may not join a cloud that already has a copy")
    func joinRuleRefusesADeviceWithData() async throws {
        let suite = "sync-activation-join"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        let service = try makeService(
            suite: suite,
            transfer: SnapshotTransfer(snapshot: OttoDataSnapshot(subscriptions: [subscription])),
            cloud: FakeCloud(copyExists: .success(true))
        )

        await #expect(throws: SyncActivationError.cloudCopyExists) {
            try await service.enableSync(
                exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
            )
        }
        #expect(try loadState(suite).isEnabled == false)
    }

    @Test("an empty device joins an existing cloud copy, without needing the check at all")
    func emptyDeviceJoinsWithoutTheCheck() async throws {
        let suite = "sync-activation-empty-join"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        // Unreachable on purpose: an empty device has nothing to collide, so
        // the one check it does not need must not be able to stop it.
        let cloud = FakeCloud(copyExists: .failure(.cloudUnreachable))
        let service = try makeService(suite: suite, transfer: SnapshotTransfer(), cloud: cloud)

        try await service.enableSync(
            exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
        )

        #expect(try loadState(suite).isEnabled)
        #expect(await cloud.copyChecks == 0)
    }

    @Test("a device with records may not join when iCloud cannot answer: refused, never assumed clear")
    func unreachableCloudRefusesADeviceWithData() async throws {
        let suite = "sync-activation-unreachable"
        try resetSuite(suite)
        defer { try? resetSuite(suite) }
        let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        let service = try makeService(
            suite: suite,
            transfer: SnapshotTransfer(snapshot: OttoDataSnapshot(subscriptions: [subscription])),
            cloud: FakeCloud(copyExists: .failure(.cloudUnreachable))
        )

        await #expect(throws: SyncActivationError.cloudUnreachable) {
            try await service.enableSync(
                exportedAt: Date(timeIntervalSince1970: 10_000), today: try day(2026, 8, 7)
            )
        }
        #expect(try loadState(suite).isEnabled == false)
    }

    @Test("every refusal has words for the screen", arguments: [
        SyncActivationError.cloudUnavailable, .cloudUnreachable, .accountUnavailable,
        .killSwitchNotEngaged, .killSwitchNotYetInEffect, .killSwitchEngaged, .cloudCopyExists
    ])
    func everyRefusalIsDescribed(error: SyncActivationError) {
        #expect(error.errorDescription?.isEmpty == false)
    }
}
