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

    func restore(_ snapshot: OttoDataSnapshot, at instant: Date) async throws {}
    func resetMaterializationWatermarks() async throws {}
}

private actor SpyZonePurger: CloudZonePurging {
    private(set) var purgeCalls = 0

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
        zonePurger: any CloudZonePurging = UnavailableZonePurger()
    ) throws -> SyncActivationService {
        SyncActivationService(
            transfer: transfer,
            userDefaults: try #require(UserDefaults(suiteName: suite)),
            snapshotDirectory: try scratchDirectory(),
            zonePurger: zonePurger
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
        let purger = SpyZonePurger()
        let service = try makeService(suite: suite, transfer: SnapshotTransfer(), zonePurger: purger)

        await #expect(throws: SyncActivationError.killSwitchNotEngaged) {
            try await service.purgeCloudZone()
        }
        #expect(await purger.purgeCalls == 0)

        await service.engageKillSwitch()
        try await service.purgeCloudZone()
        #expect(await purger.purgeCalls == 1)
    }

    @Test("with CloudKit off, the default purger refuses loudly instead of pretending")
    func defaultPurgerRefuses() async throws {
        await #expect(throws: SyncActivationError.cloudUnavailable) {
            try await UnavailableZonePurger().purgeZone()
        }
    }
}
