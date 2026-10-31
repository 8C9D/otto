import Foundation

/// What THIS LAUNCH's main store is doing about sync (spec §8, Wave 6B).
///
/// Distinct from `SyncState`, which holds the persisted switches: the switches
/// act at the next launch, so mid-session the flags and the live container can
/// disagree in exactly the window an incident occupies. Anything that has to
/// know whether the store is mirroring right now reads this, never the flags.
public enum SyncSessionMode: String, Hashable, Sendable {
    case off
    case mirrored
}

/// Why a sync step failed, reduced to what the app can act on or say.
public enum SyncFailure: Hashable, Sendable {
    /// No usable iCloud account: signed out, or iCloud turned off for Otto.
    case accountUnavailable
    /// iCloud could not be reached right now; the framework retries by itself.
    case networkUnavailable
    /// The user's iCloud storage is full, so changes stop leaving this device.
    case quotaExceeded
    /// Anything else, by its `CKError` code - the log's diagnosis, not the
    /// user's problem to decode.
    case other(code: Int)
}

/// One step of the mirroring lifecycle, as the framework reported it.
///
/// **Evidence about the subsystem, never about Otto's code** (spec §9b): a
/// `succeeded` import says CloudKit finished what it was doing, not that the
/// data on screen is right. It is a trigger for the checks, not a result.
public struct SyncEvent: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case setup
        case `import`
        case export
    }

    public enum Phase: Hashable, Sendable {
        case started
        case succeeded
        case failed(SyncFailure)
    }

    public var kind: Kind
    public var phase: Phase

    public init(kind: Kind, phase: Phase) {
        self.kind = kind
        self.phase = phase
    }
}

/// The stream of mirroring events. A seam, because the real source is a
/// `CoreData` notification only the persistence adapter may name, and the
/// coordinator above it has to be testable with no CloudKit in the process.
public protocol SyncEventSource: Sendable {
    var events: AsyncStream<SyncEvent> { get }
}
