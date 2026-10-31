import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §8 (Wave 6B-Prep): the store-side prerequisites for enabling CloudKit,
// built and tested while there is nothing to lose.
extension SerializedPersistenceTests {
    @Suite("Sync prerequisites at the store (spec §8)")
    struct SyncPrerequisiteTests {

        private let instant = Date(timeIntervalSince1970: 11_000)

        @Test("a restore tombstones records the snapshot does not carry - never hard-deletes")
        func restoreTombstonesAbsentees() async throws {
            let (store, _) = try makeStore()
            let kept = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            let dropped = try makeSubscription(index: 2, cycleStartDay: try day(2026, 2, 1))
            try await store.save(kept)
            try await store.save(dropped)
            try await store.save(
                try makeBillingEvent(index: 101, subscriptionID: dropped.id, expectedDate: try day(2026, 2, 1))
            )

            try await store.restore(
                OttoDataSnapshot(subscriptions: [kept]), at: instant, watermarks: .reconstruct
            )

            #expect(try await store.subscriptions().map(\.id) == [kept.id])
            // The dropped subscription and its cascade are history, not gone:
            // under mirroring this restore syncs as ordinary tombstone edits,
            // not a mass cloud deletion (spec §8 prerequisite 4).
            let all = try await store.subscriptionsIncludingDeleted()
            let tombstone = try #require(all.first { $0.id == dropped.id })
            #expect(tombstone.deletedAt == instant)
            let events = try await store.eventsIncludingDeleted(forSubscription: dropped.id)
            #expect(events.allSatisfy { $0.deletedAt == instant })
        }

        @Test("a restore diffs children explicitly: an episode the aggregate no longer carries is tombstoned")
        func restoreDiffsChildren() async throws {
            let (store, _) = try makeStore()
            let closed = PauseEpisode(
                id: try fixtureUUID(701),
                startedOn: try day(2026, 2, 1),
                scheduledResumeOn: nil,
                endedOn: try day(2026, 3, 1),
                outcome: .resumed,
                createdAt: Date(timeIntervalSince1970: 3_000),
                updatedAt: Date(timeIntervalSince1970: 3_000)
            )
            var subscription = try makeSubscription(
                index: 1, cycleStartDay: try day(2026, 1, 15), pauseEpisodes: [closed]
            )
            try await store.save(subscription)

            // The snapshot's copy of the aggregate has no episodes: a restore
            // IS the whole-database statement, so - unlike a save (§4a) - it
            // may and must remove the child, as a tombstone.
            subscription.pauseEpisodes = []
            try await store.restore(
                OttoDataSnapshot(subscriptions: [subscription]), at: instant, watermarks: .reconstruct
            )

            let reloaded = try #require(try await store.subscription(withID: subscription.id))
            let episode = try #require(reloaded.pauseEpisodes.first { $0.id == closed.id })
            #expect(episode.deletedAt == instant)
        }

        @Test("a restore never overwrites an earlier tombstone's instant")
        func restoreKeepsEarlierTombstones() async throws {
            let (store, _) = try makeStore()
            let subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
            try await store.save(subscription)
            try await store.deleteSubscription(withID: subscription.id, at: Date(timeIntervalSince1970: 9_000))

            try await store.restore(OttoDataSnapshot(), at: instant, watermarks: .reconstruct)

            let all = try await store.subscriptionsIncludingDeleted()
            #expect(all.first?.deletedAt == Date(timeIntervalSince1970: 9_000))
        }

        @Test("mirroring takes the flag, a released brake AND a build with a container - and the kill switch always wins")
        func killSwitchGovernsSyncMode() {
            let container = "iCloud.com.arthurzhang.otto"
            let mirrored = OttoContainerFactory.MainStoreSyncMode.cloudKitPrivate(containerIdentifier: container)
            let mode = OttoContainerFactory.mainStoreSyncMode(for:cloudContainerIdentifier:)

            // Spec §8 4a's day-one test: the enum has its second case, so the
            // decision can now actually answer something other than .off.
            #expect(mode(SyncState(isEnabled: true, killSwitchEngaged: false), container) == mirrored)
            #expect(mode(SyncState(), container) == .off)
            // An engaged kill switch beats an enabled sync, unconditionally.
            #expect(mode(SyncState(isEnabled: true, killSwitchEngaged: true), container) == .off)
            #expect(mode(SyncState(isEnabled: false, killSwitchEngaged: true), container) == .off)
            // A build that names no container cannot mirror, whatever the
            // flags say - it is what holds a release off production.
            #expect(mode(SyncState(isEnabled: true, killSwitchEngaged: false), nil) == .off)
            #expect(mode(SyncState(isEnabled: true, killSwitchEngaged: false), "") == .off)
        }

        @Test("the mirrored mode maps to the private database and reports itself as mirrored")
        func mirroredModeReachesThePrivateDatabase() {
            let mode = OttoContainerFactory.MainStoreSyncMode.cloudKitPrivate(containerIdentifier: "iCloud.example")
            #expect(mode.sessionMode == .mirrored)
            #expect(OttoContainerFactory.MainStoreSyncMode.off.sessionMode == .off)
            // `.private`'s associated value has no public reader, so its
            // description is the only thing a test can hold it to.
            #expect(String(describing: mode.cloudKitDatabase).contains("iCloud.example"))
        }

        @Test("restore refuses in a session that opened mirrored, even after the kill switch is thrown")
        func restoreRefusesInAMirroredSession() async throws {
            // §8 4a: `mainSyncMode != .off` could not be true until the enum
            // grew, so this guard had never once fired. The flags say restore
            // is fine - the switch is engaged - but it acts at the NEXT launch,
            // and this session's store is still mirroring.
            let containers = try containerCreationLock.withLock {
                try OttoContainerFactory.inMemoryContainers(
                    recordingSyncMode: .cloudKitPrivate(containerIdentifier: "iCloud.example")
                )
            }
            let store = OttoStore(
                containers: containers,
                syncState: { SyncState(isEnabled: true, killSwitchEngaged: true) }
            )
            await #expect(throws: RepositoryError.restoreRequiresSyncDisengaged) {
                try await store.restore(OttoDataSnapshot(), at: Date(timeIntervalSince1970: 9_000), watermarks: .keep)
            }
            #expect(containers.syncSessionMode == .mirrored)
        }

        @Test("a mirrored open that fails falls back to the local store and says so; a local failure still throws")
        func failedMirroredOpenFallsBack() throws {
            struct OpenFailure: Error {}
            let mirrored = OttoContainerFactory.MainStoreSyncMode.cloudKitPrivate(containerIdentifier: "iCloud.example")
            var attempts: [(OttoContainerFactory.MainStoreSyncMode, Bool)] = []

            let opened = try OttoContainerFactory.opening(mirrored) { mode, failed in
                attempts.append((mode, failed))
                guard mode == .off else { throw OpenFailure() }
                return try containerCreationLock.withLock {
                    let memory = try OttoContainerFactory.inMemoryContainers()
                    return OttoContainers(
                        main: memory.main, deviceState: memory.deviceState,
                        mainSyncMode: mode, mirroredOpenFailed: failed
                    )
                }
            }
            #expect(attempts.map(\.0) == [mirrored, .off])
            #expect(opened.mirroredOpenFailed)
            #expect(opened.syncSessionMode == .off)

            // A LOCAL failure has nothing to fall back to: one attempt, thrown.
            var localAttempts = 0
            #expect(throws: OpenFailure.self) {
                try OttoContainerFactory.opening(.off) { _, _ in
                    localAttempts += 1
                    throw OpenFailure()
                }
            }
            #expect(localAttempts == 1)
        }

        @Test("the sync switches persist and load without a container")
        func syncStateRoundTrips() throws {
            let defaults = try #require(UserDefaults(suiteName: "sync-state-tests"))
            defer { defaults.removePersistentDomain(forName: "sync-state-tests") }

            #expect(SyncState.load(from: defaults) == SyncState())

            SyncState.setEnabled(true, in: defaults)
            SyncState.setKillSwitchEngaged(true, in: defaults)
            #expect(SyncState.load(from: defaults) == SyncState(isEnabled: true, killSwitchEngaged: true))

            // Disengaging the brake restores the previous state - the enable
            // flag was deliberately untouched by the kill switch.
            SyncState.setKillSwitchEngaged(false, in: defaults)
            #expect(SyncState.load(from: defaults) == SyncState(isEnabled: true, killSwitchEngaged: false))

            // The raw keys ARE the persisted format: renaming one silently
            // resets that switch on every real device while a round-trip test
            // stays green. Pinned by the Wave 6B-Prep-2 sweep.
            #expect(defaults.object(forKey: "sync.enabled") as? Bool == true)
            #expect(defaults.object(forKey: "sync.killSwitchEngaged") as? Bool == false)
        }
    }
}
