import Foundation
import OttoDomain
import OttoRepositories

/// The cloud-side half of the zone purge (spec §8): deleting the app's CloudKit
/// record zone.
public protocol CloudZonePurging: Sendable {
    func purgeZone() async throws
}

/// What iCloud says about the account on this device.
public enum CloudAccountStatus: Hashable, Sendable {
    case available
    /// Signed out, or iCloud turned off for Otto. Under mirroring this is not a
    /// pause: the framework clears the synced store from the device, by design.
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown
}

/// Everything the enable and purge flows ask of iCloud. A seam, so the rules
/// that protect the user's data are testable with no CloudKit in the process.
public protocol CloudSyncClient: CloudZonePurging {
    func accountStatus() async -> CloudAccountStatus
    /// Whether another device has already put an Otto copy in this account.
    func cloudCopyExists() async throws -> Bool
}

/// For a build with no container to talk to. Every question refuses loudly -
/// claiming to have purged a zone, or that iCloud is empty, would be exactly
/// the reassuring boundary this project refuses to draw.
public struct UnavailableCloudSyncClient: CloudSyncClient {
    public init() {}

    public func accountStatus() async -> CloudAccountStatus { .unknown }

    public func cloudCopyExists() async throws -> Bool {
        throw SyncActivationError.cloudUnavailable
    }

    public func purgeZone() async throws {
        throw SyncActivationError.cloudUnavailable
    }
}

public enum SyncActivationError: Error, Hashable {
    /// This build has no CloudKit container to talk to.
    case cloudUnavailable
    /// iCloud could not be reached, so the check that guards this action never
    /// ran. Refused rather than assumed clear.
    case cloudUnreachable
    /// No usable iCloud account on this device.
    case accountUnavailable
    /// A purge was requested while sync could still run: purging a zone that
    /// devices are actively syncing re-uploads the local copy into the fresh
    /// zone. Engage the kill switch first, deliberately.
    case killSwitchNotEngaged
    /// The kill switch is engaged but acts at the next launch, and THIS
    /// session's store is still mirroring - it would recreate the zone it was
    /// just told to forget. The same trap `restore()`'s guard closes.
    case killSwitchNotYetInEffect
    /// Enabling sync while the kill switch is engaged: the brake exists to
    /// need a deliberate, separate release - never an implicit one.
    case killSwitchEngaged
    /// iCloud already holds an Otto copy and this device holds records too.
    ///
    /// CloudKit does not identify records by Otto's ids: the same subscription
    /// on two devices (one backup, imported on both) uploads as two records
    /// with one id, permanently, and no rule can tell two identical twins apart
    /// the same way on both devices. So a device joins empty.
    case cloudCopyExists
}

extension SyncActivationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cloudUnavailable:
            String(localized: "iCloud sync isn't available in this version of Otto.")
        case .cloudUnreachable:
            String(localized: "Otto couldn't reach iCloud. Nothing changed - try again when you're online.")
        case .accountUnavailable:
            String(localized: "Sign in to iCloud in the Settings app, and make sure iCloud is on for Otto.")
        case .killSwitchNotEngaged:
            String(localized: "Stop syncing first, then reopen Otto.")
        case .killSwitchNotYetInEffect:
            String(localized: "Sync is still running until Otto is reopened. Close Otto, open it again, and retry.")
        case .killSwitchEngaged:
            String(localized: "Resume syncing instead - sync was stopped on this device, not turned off.")
        case .cloudCopyExists:
            String(localized: """
            iCloud already has Otto data, and this device has its own. Merging them \
            would duplicate your subscriptions. To use iCloud's copy, export anything \
            you want to keep, delete and reinstall Otto, and turn on sync before \
            adding anything.
            """)
        }
    }
}

/// The sync on/off machinery built BEFORE there is anything to lose
/// (spec §8, Wave 6B-Prep): the pre-enable snapshot, the kill switch, and the
/// zone-purge action. The Settings screen calls this; nothing else turns sync
/// on, because this is the only path that takes the snapshot first.
public actor SyncActivationService {

    private let transfer: any DataTransferRepository
    private let userDefaults: UserDefaults
    private let snapshotDirectory: URL
    private let cloud: any CloudSyncClient
    private let sessionMode: SyncSessionMode

    /// `snapshotDirectory` defaults to the user's Documents directory - with
    /// file sharing enabled it is visible in the Files app, which is what
    /// "stored where the user can find it" means. Tests point it elsewhere.
    public init(
        transfer: any DataTransferRepository,
        userDefaults: UserDefaults = .standard,
        snapshotDirectory: URL? = nil,
        cloud: any CloudSyncClient = UnavailableCloudSyncClient(),
        sessionMode: SyncSessionMode = .off
    ) {
        self.transfer = transfer
        self.userDefaults = userDefaults
        self.snapshotDirectory = snapshotDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cloud = cloud
        self.sessionMode = sessionMode
    }

    public var syncState: SyncState { .load(from: userDefaults) }

    /// Turns sync on - AFTER the automatic pre-enable snapshot is durably on
    /// disk, unprompted (spec §8 prerequisite 1). Ordering is the point: the
    /// flag flips last, so a failed export means sync stays off and there is
    /// always a pre-sync restore point once it is on. Returns the snapshot's
    /// location so the UI can say where it is.
    ///
    /// What the snapshot does NOT protect against: anything created between
    /// this instant and a future incident (it is a floor, not a mirror), and
    /// a failure of the disk it sits on - it lives on this device, beside the
    /// data it backs up.
    @discardableResult
    public func enableSync(exportedAt: Date, today: CalendarDay) async throws -> URL {
        guard !syncState.killSwitchEngaged else { throw SyncActivationError.killSwitchEngaged }
        // Before anything is written. An account that cannot sync would leave
        // a "sync is on" flag that nothing behind it can honour.
        guard await cloud.accountStatus() == .available else { throw SyncActivationError.accountUnavailable }
        let snapshot = try await transfer.completeSnapshot()
        // The join rule: the first device uploads, and every later one arrives
        // empty. Only asked of a device with records: an empty one has nothing
        // to collide, so it can join even when this check cannot be answered.
        if !snapshot.isEmpty, try await cloud.cloudCopyExists() {
            throw SyncActivationError.cloudCopyExists
        }
        let data = try exportData(from: snapshot, exportedAt: exportedAt)
        let url = snapshotDirectory.appendingPathComponent("Otto-PreSync-Backup-\(today).json")
        try data.write(to: url, options: .atomic)
        SyncState.setEnabled(true, in: userDefaults)
        return url
    }

    /// The emergency brake (spec §8 prerequisite 2): stops sync from the next
    /// launch, no build required. Deliberately does NOT clear the enable flag,
    /// so disengaging restores the previous state; deliberately takes no other
    /// action - stopping the bleeding must never wait on anything.
    public func engageKillSwitch() {
        SyncState.setKillSwitchEngaged(true, in: userDefaults)
    }

    public func disengageKillSwitch() {
        SyncState.setKillSwitchEngaged(false, in: userDefaults)
    }

    /// The zone-purge action (spec §8 prerequisite 3): deletes the cloud copy.
    /// Refuses unless the kill switch is engaged AND has taken effect - purging
    /// a zone that devices are still syncing re-uploads local copies into the
    /// fresh zone, which is resurrection at zone scale, and a session that
    /// opened mirrored is one of those devices until it is relaunched.
    ///
    /// On success this device returns to plain off rather than stopped: there
    /// is no cloud copy left to resume, so turning sync on again is a fresh
    /// start through `enableSync`, with its own snapshot.
    ///
    /// What it does NOT protect against: other devices' LOCAL copies, and an
    /// offline device that re-enables sync later re-creating the zone from its
    /// own data. The documented recovery is purge → restore from a chosen
    /// export → re-enable.
    public func purgeCloudZone() async throws {
        guard syncState.killSwitchEngaged else { throw SyncActivationError.killSwitchNotEngaged }
        guard sessionMode == .off else { throw SyncActivationError.killSwitchNotYetInEffect }
        try await cloud.purgeZone()
        SyncState.setEnabled(false, in: userDefaults)
        SyncState.setKillSwitchEngaged(false, in: userDefaults)
    }
}
