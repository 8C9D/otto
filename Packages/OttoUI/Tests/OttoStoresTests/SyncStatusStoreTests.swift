import Foundation
import OttoDomain
import OttoRepositories
import OttoServices
import Testing
@testable import OttoStores

private actor EmptyTransfer: DataTransferRepository {
    func completeSnapshot() async throws -> OttoDataSnapshot { OttoDataSnapshot() }
    func restore(_ snapshot: OttoDataSnapshot, at instant: Date, watermarks: RestoreWatermarkPolicy) async throws {}
    func reconstructMaterializationWatermarks() async throws {}
}

private struct StubCloud: CloudSyncClient {
    var account: CloudAccountStatus = .available
    func accountStatus() async -> CloudAccountStatus { account }
    func cloudCopyExists() async throws -> Bool { false }
    func purgeZone() async throws {}
}

/// Parks the settling limit until a test expires it, so "the limit passed" is a
/// statement in the test rather than five real minutes.
private actor Expiry {
    private var waiters: [CheckedContinuation<Void, any Error>] = []
    private(set) var armed = 0

    func wait() async throws {
        armed += 1
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func expire() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@Suite("Sync status (spec §8, Wave 6B)", .serialized)
@MainActor
struct SyncStatusStoreTests {

    private func suite(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeStore(
        sessionMode: SyncSessionMode = .mirrored,
        state: SyncState = SyncState(isEnabled: true),
        account: CloudAccountStatus = .available,
        expiry: Expiry = Expiry(),
        suiteName: String = "sync-status-store"
    ) throws -> SyncStatusStore {
        let defaults = try suite(suiteName)
        SyncState.setEnabled(state.isEnabled, in: defaults)
        SyncState.setKillSwitchEngaged(state.killSwitchEngaged, in: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cloud = StubCloud(account: account)
        return SyncStatusStore(
            activation: try Self.activation(
                suiteName: suiteName, directory: directory, cloud: cloud, sessionMode: sessionMode
            ),
            cloud: cloud,
            initialState: state,
            sessionMode: sessionMode,
            isAvailable: true,
            dates: .fixed(today: try #require(CalendarDay(year: 2026, month: 10, day: 31))),
            sleep: { _ in try await expiry.wait() }
        )
    }

    /// Nonisolated because `UserDefaults` isn't Sendable and can't cross from
    /// this main-actor suite into the service: it opens its own instance.
    private nonisolated static func activation(
        suiteName: String, directory: URL, cloud: StubCloud, sessionMode: SyncSessionMode
    ) throws -> SyncActivationService {
        SyncActivationService(
            transfer: EmptyTransfer(),
            userDefaults: try #require(UserDefaults(suiteName: suiteName)),
            snapshotDirectory: directory,
            cloud: cloud,
            sessionMode: sessionMode
        )
    }

    private func activity(
        importing: Bool = false, finished: Bool = false, failure: SyncFailure? = nil
    ) -> SyncActivity {
        var activity = SyncActivity()
        activity.isImporting = importing
        activity.hasFinishedImport = finished
        activity.importFailure = failure
        return activity
    }

    // MARK: - What the device is doing

    @Test("what Settings offers follows the switches AND the session", arguments: [
        (SyncState(), SyncSessionMode.off, SyncPresentation.off),
        (SyncState(isEnabled: true), .off, .startsNextLaunch),
        (SyncState(isEnabled: true), .mirrored, .syncing),
        (SyncState(isEnabled: true, killSwitchEngaged: true), .mirrored, .stopsNextLaunch),
        (SyncState(isEnabled: true, killSwitchEngaged: true), .off, .stopped)
    ])
    func presentationTable(state: SyncState, session: SyncSessionMode, expected: SyncPresentation) {
        #expect(SyncPresentation.derive(
            isAvailable: true, state: state, sessionMode: session, mirroredOpenFailed: false
        ) == expected)
    }

    @Test("a build with no container offers nothing, whatever the flags left over from another build say")
    func unavailableBuild() {
        #expect(SyncPresentation.derive(
            isAvailable: false, state: SyncState(isEnabled: true), sessionMode: .off, mirroredOpenFailed: false
        ) == .unavailable)
    }

    @Test("a failed mirrored open is reported until the user stops the retries")
    func failedOpen() {
        let enabled = SyncState(isEnabled: true)
        #expect(SyncPresentation.derive(
            isAvailable: true, state: enabled, sessionMode: .off, mirroredOpenFailed: true
        ) == .failedToOpen)
        #expect(SyncPresentation.derive(
            isAvailable: true, state: SyncState(isEnabled: true, killSwitchEngaged: true),
            sessionMode: .off, mirroredOpenFailed: true
        ) == .stopped)
    }

    @Test("each action moves the presentation, without pretending the session changed")
    func actionsMoveThePresentation() async throws {
        let store = try makeStore(sessionMode: .off, state: SyncState(), suiteName: "sync-status-actions")
        #expect(store.presentation == .off)

        try await store.turnOn()
        #expect(store.presentation == .startsNextLaunch)

        await store.stopSyncing()
        #expect(store.presentation == .stopped)

        await store.resumeSyncing()
        #expect(store.presentation == .startsNextLaunch)

        await store.stopSyncing()
        try await store.deleteCloudCopy()
        #expect(store.presentation == .off)
    }

    // MARK: - Settling

    @Test("a mirrored launch settles until an import finishes")
    func settlesUntilFirstImport() throws {
        let store = try makeStore()
        #expect(store.isSettling)
        store.apply(activity(importing: true))
        #expect(store.isSettling)
        store.apply(activity(finished: true))
        #expect(!store.isSettling)
    }

    @Test("a later import settles again")
    func laterImportSettles() throws {
        let store = try makeStore()
        store.apply(activity(finished: true))
        store.apply(activity(importing: true, finished: true))
        #expect(store.isSettling)
    }

    @Test("a session that isn't mirroring never settles")
    func localSessionNeverSettles() throws {
        #expect(!(try makeStore(sessionMode: .off).isSettling))
    }

    @Test("settling cannot outlive its limit: an import that never finishes must not hide real damage for good")
    func settlingIsBounded() async throws {
        let expiry = Expiry()
        let store = try makeStore(expiry: expiry)
        #expect(store.isSettling)
        while await expiry.armed < 1 { await Task.yield() }

        await expiry.expire()
        while store.isSettling { await Task.yield() }
        #expect(!store.isSettling)
    }

    @Test("a new import restarts the limit, because it can bring new transients")
    func newImportRestartsTheLimit() async throws {
        let expiry = Expiry()
        let store = try makeStore(expiry: expiry)
        while await expiry.armed < 1 { await Task.yield() }
        await expiry.expire()
        while store.isSettling { await Task.yield() }

        store.apply(activity(importing: true))
        #expect(store.isSettling)
    }

    // MARK: - The account

    @Test("a signed-out mirrored device says so, and stops claiming records are on their way")
    func signedOut() async throws {
        let store = try makeStore(account: .noAccount)
        await store.refreshAccount()
        #expect(store.isAccountMissing)
        #expect(!store.isSettling)
    }

    @Test("an available account is not missing, and an unknown one is not assumed gone")
    func accountNotMissing() async throws {
        let available = try makeStore()
        await available.refreshAccount()
        #expect(!available.isAccountMissing)

        let unknown = try makeStore(account: .unknown)
        await unknown.refreshAccount()
        #expect(!unknown.isAccountMissing)
    }

    @Test("a session that isn't mirroring never asks: signing out cannot touch a local store")
    func localSessionIgnoresTheAccount() async throws {
        let store = try makeStore(sessionMode: .off, account: .noAccount)
        await store.refreshAccount()
        #expect(store.account == nil)
        #expect(!store.isAccountMissing)
    }

    @Test("an account failure during sync re-reads the account")
    func accountFailureRefreshes() async throws {
        let store = try makeStore(account: .noAccount)
        #expect(store.account == nil)
        store.apply(activity(failure: .accountUnavailable))
        while store.account == nil { await Task.yield() }
        #expect(store.isAccountMissing)
    }

    // MARK: - Another device's changes reaching the screens

    @Test("an open detail screen catches up: it holds a snapshot nothing else would refresh")
    func convergenceRefreshesOpenDetails() async throws {
        let subscriptions = MockSubscriptionRepository()
        let model = AppModel(repositories: AppModel.Repositories(
            subscriptions: subscriptions,
            billingEvents: MockBillingEventRepository(),
            cancellations: MockCancellationRepository(),
            priceChanges: MockPriceChangeRepository(),
            paymentMethods: MockPaymentMethodRepository(),
            transfer: EmptyTransfer()
        ), dates: .fixed(today: try day(2026, 10, 31)))
        var subscription = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        try await subscriptions.save(subscription)
        let detail = model.detailStore(for: subscription.id)
        await detail.refresh()

        subscription.name = "Renamed on another device"
        try await subscriptions.save(subscription)
        await model.syncDidConverge()

        #expect(detail.state.value?.subscription.name == "Renamed on another device")
    }

    @Test("a detail screen that closed is let go: the model must not keep it alive")
    func closedDetailsAreReleased() async throws {
        let model = AppModel(repositories: AppModel.Repositories(
            subscriptions: MockSubscriptionRepository(),
            billingEvents: MockBillingEventRepository(),
            cancellations: MockCancellationRepository(),
            priceChanges: MockPriceChangeRepository(),
            paymentMethods: MockPaymentMethodRepository(),
            transfer: EmptyTransfer()
        ), dates: .fixed(today: try day(2026, 10, 31)))
        weak var released: SubscriptionDetailStore?
        do {
            let detail = model.detailStore(for: UUID())
            released = detail
            #expect(released != nil)
        }
        #expect(released == nil)
        await model.syncDidConverge()
    }
}
