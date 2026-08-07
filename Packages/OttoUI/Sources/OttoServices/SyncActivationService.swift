import Foundation
import OttoDomain
import OttoRepositories

/// The cloud-side half of the zone purge (spec §8, Wave 6B-Prep): deleting
/// the app's CloudKit record zone. A seam, because with CloudKit off there is
/// no zone and no CKDatabase to reach - Wave 6B supplies the real
/// implementation; until then the default refuses LOUDLY rather than
/// pretending a purge happened.
public protocol CloudZonePurging: Sendable {
    func purgeZone() async throws
}

/// The pre-6B implementation: there is no cloud zone while CloudKit is off,
/// and claiming to have purged one would be the reassuring boundary this
/// project refuses to draw. Always throws.
public struct UnavailableZonePurger: CloudZonePurging {
    public init() {}

    public func purgeZone() async throws {
        throw SyncActivationError.cloudUnavailable
    }
}

public enum SyncActivationError: Error, Hashable {
    /// The zone purge (or a future cloud call) has no CloudKit to talk to.
    case cloudUnavailable
    /// A purge was requested while sync could still run: purging a zone that
    /// devices are actively syncing re-uploads the local copy into the fresh
    /// zone. Engage the kill switch first, deliberately.
    case killSwitchNotEngaged
    /// Enabling sync while the kill switch is engaged: the brake exists to
    /// need a deliberate, separate release - never an implicit one.
    case killSwitchEngaged
}

/// The sync on/off machinery built BEFORE there is anything to lose
/// (spec §8, Wave 6B-Prep): the pre-enable snapshot, the kill switch, and the
/// zone-purge action. Wave 6B's enable UI calls this; nothing else turns sync
/// on, because this is the only path that takes the snapshot first.
public actor SyncActivationService {

    private let transfer: any DataTransferRepository
    private let userDefaults: UserDefaults
    private let snapshotDirectory: URL
    private let zonePurger: any CloudZonePurging

    /// `snapshotDirectory` defaults to the user's Documents directory - with
    /// file sharing enabled it is visible in the Files app, which is what
    /// "stored where the user can find it" means. Tests point it elsewhere.
    public init(
        transfer: any DataTransferRepository,
        userDefaults: UserDefaults = .standard,
        snapshotDirectory: URL? = nil,
        zonePurger: any CloudZonePurging = UnavailableZonePurger()
    ) {
        self.transfer = transfer
        self.userDefaults = userDefaults
        self.snapshotDirectory = snapshotDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.zonePurger = zonePurger
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
        let snapshot = try await transfer.completeSnapshot()
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
    /// Refuses unless the kill switch is engaged - purging a zone that devices
    /// are still syncing re-uploads local copies into the fresh zone, which is
    /// resurrection at zone scale.
    ///
    /// What it does NOT protect against: other devices' LOCAL copies (purging
    /// the cloud deletes nothing on any device), and an offline device that
    /// re-enables sync later re-creating the zone from its own data. The
    /// documented recovery is purge → restore from a chosen export → re-enable.
    public func purgeCloudZone() async throws {
        guard syncState.killSwitchEngaged else { throw SyncActivationError.killSwitchNotEngaged }
        try await zonePurger.purgeZone()
    }
}
