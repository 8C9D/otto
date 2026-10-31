import Foundation
import Observation
import OttoDomain
import OttoRepositories
import OttoServices

/// Which of Settings' sync states this device is in. Pure, so the mapping from
/// switches and session to what the user is offered is testable as a table.
public enum SyncPresentation: Hashable, Sendable {
    /// This build names no CloudKit container.
    case unavailable
    case off
    /// Turned on; the store opens mirrored at the next launch.
    case startsNextLaunch
    case syncing
    /// The brake is thrown, and this session's store is still mirroring.
    case stopsNextLaunch
    case stopped
    /// Mirroring was asked for and the store could not open that way.
    case failedToOpen

    /// The switches act at the next launch, so what this device is doing takes
    /// both them and the session.
    static func derive(
        isAvailable: Bool, state: SyncState, sessionMode: SyncSessionMode, mirroredOpenFailed: Bool
    ) -> SyncPresentation {
        if mirroredOpenFailed, !state.killSwitchEngaged { return .failedToOpen }
        guard isAvailable else { return .unavailable }
        switch sessionMode {
        case .mirrored:
            return state.killSwitchEngaged ? .stopsNextLaunch : .syncing
        case .off:
            if state.killSwitchEngaged { return .stopped }
            return state.isEnabled ? .startsNextLaunch : .off
        }
    }
}

/// What the screens need to know about sync. Nothing here decides anything:
/// `SyncActivationService` owns the switches and `SyncCoordinator` the pass.
@MainActor
@Observable
public final class SyncStatusStore {

    public let sessionMode: SyncSessionMode
    public let isAvailable: Bool
    public let mirroredOpenFailed: Bool
    public private(set) var state: SyncState
    public private(set) var activity = SyncActivity()
    public private(set) var account: CloudAccountStatus?

    private let activation: SyncActivationService
    private let cloud: any CloudSyncClient
    private let dates: DateProvider
    private let settlingLimit: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var settlingTimedOut = false
    @ObservationIgnored private var settlingTimer: Task<Void, Never>?

    public init(
        activation: SyncActivationService,
        cloud: any CloudSyncClient,
        initialState: SyncState,
        sessionMode: SyncSessionMode,
        isAvailable: Bool,
        mirroredOpenFailed: Bool = false,
        dates: DateProvider = .live,
        settlingLimit: Duration = .seconds(300),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.activation = activation
        self.cloud = cloud
        self.state = initialState
        self.sessionMode = sessionMode
        self.isAvailable = isAvailable
        self.mirroredOpenFailed = mirroredOpenFailed
        self.dates = dates
        self.settlingLimit = settlingLimit
        self.sleep = sleep
        if sessionMode == .mirrored {
            armSettlingTimer()
        }
    }

    public var presentation: SyncPresentation {
        .derive(
            isAvailable: isAvailable, state: state,
            sessionMode: sessionMode, mirroredOpenFailed: mirroredOpenFailed
        )
    }

    /// Records may be mid-arrival, so "couldn't be read" probably means "not
    /// here yet" (the readiness audit's row 4).
    ///
    /// **Bounded on purpose.** Today hides real damage while this is true, so it
    /// cannot be allowed to stay true: an import that never finishes, or a
    /// device with no network, must fall back to showing every card. The limit
    /// restarts with each import, because each one can bring new transients.
    public var isSettling: Bool {
        guard sessionMode == .mirrored, !settlingTimedOut, !isAccountMissing else { return false }
        return activity.isImporting || !activity.hasFinishedImport
    }

    /// Mirroring with no iCloud account. The framework clears a signed-out
    /// account's synced records from the device by design, so an empty Today
    /// here means "in your iCloud", not "you have no subscriptions" - and
    /// reminders stop with them, which nothing else on screen would say.
    public var isAccountMissing: Bool {
        sessionMode == .mirrored && account == .noAccount
    }

    public func apply(_ activity: SyncActivity) {
        let importBegan = activity.isImporting && !self.activity.isImporting
        self.activity = activity
        if importBegan {
            armSettlingTimer()
        }
        if activity.lastFailure == .accountUnavailable {
            Task { await refreshAccount() }
        }
    }

    public func refreshAccount() async {
        guard sessionMode == .mirrored else { return }
        account = await cloud.accountStatus()
    }

    /// Takes the pre-sync snapshot and flips the flag. Returns the file's
    /// location so the screen can say where the backup went.
    @discardableResult
    public func turnOn() async throws -> URL {
        let url = try await activation.enableSync(exportedAt: dates.now(), today: dates.today())
        await reloadState()
        return url
    }

    public func stopSyncing() async {
        await activation.engageKillSwitch()
        await reloadState()
    }

    public func resumeSyncing() async {
        await activation.disengageKillSwitch()
        await reloadState()
    }

    public func deleteCloudCopy() async throws {
        try await activation.purgeCloudZone()
        await reloadState()
    }

    private func reloadState() async {
        state = await activation.syncState
    }

    private func armSettlingTimer() {
        settlingTimer?.cancel()
        settlingTimedOut = false
        settlingTimer = Task { [weak self, settlingLimit, sleep] in
            do {
                try await sleep(settlingLimit)
            } catch {
                return
            }
            self?.settlingTimedOut = true
        }
    }
}
