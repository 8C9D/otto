import Foundation

/// The runtime sync switches (spec §8, Wave 6B-Prep) - persisted in
/// `UserDefaults` because they must be readable BEFORE any container exists:
/// the factory consults them while deciding the main store's configuration.
///
/// Two flags, deliberately separate:
/// - `isEnabled` is the affirmative choice ("the user turned sync on"), which
///   Wave 6B's enable flow writes - only after the pre-enable snapshot is
///   durably on disk.
/// - `killSwitchEngaged` is the emergency brake: engaging it stops sync from
///   the next launch WITHOUT shipping a build and without touching the
///   enable flag, so disengaging returns to the previous state. The kill
///   switch wins over everything, including any future enablement logic.
///
/// What the kill switch does NOT protect against (honest boundary): it takes
/// effect at the next launch, not mid-flight; it does nothing on other
/// devices, which keep syncing with the cloud copy; and it removes no data,
/// local or cloud - stopping the bleeding is all it does.
public struct SyncState: Hashable, Sendable {
    public var isEnabled: Bool
    public var killSwitchEngaged: Bool

    /// Stable persistence keys - renaming one silently resets that switch.
    private enum Key {
        static let enabled = "sync.enabled"
        static let killSwitch = "sync.killSwitchEngaged"
    }

    public init(isEnabled: Bool = false, killSwitchEngaged: Bool = false) {
        self.isEnabled = isEnabled
        self.killSwitchEngaged = killSwitchEngaged
    }

    public static func load(from userDefaults: UserDefaults = .standard) -> SyncState {
        SyncState(
            isEnabled: userDefaults.bool(forKey: Key.enabled),
            killSwitchEngaged: userDefaults.bool(forKey: Key.killSwitch)
        )
    }

    public static func setEnabled(_ enabled: Bool, in userDefaults: UserDefaults = .standard) {
        userDefaults.set(enabled, forKey: Key.enabled)
    }

    public static func setKillSwitchEngaged(_ engaged: Bool, in userDefaults: UserDefaults = .standard) {
        userDefaults.set(engaged, forKey: Key.killSwitch)
    }
}
