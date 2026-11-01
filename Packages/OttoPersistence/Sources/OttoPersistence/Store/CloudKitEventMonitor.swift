import CloudKit
import CoreData
import Foundation
import OttoRepositories

/// Bridges `NSPersistentCloudKitContainer`'s event notification into
/// `SyncEvent`s - the one place above the framework that names it.
///
/// Create it BEFORE the container opens: the framework posts `setup` as soon as
/// the mirrored store loads, and an observer installed afterwards has already
/// missed it. The stream buffers, so the consumer can attach later; only the
/// newest events are kept, because the coordinator acts on the latest state.
///
/// **Observing ends when this is released**, so whoever consumes `events` must
/// hold the monitor itself, not just the stream.
///
/// SwiftData never exposes the underlying container, so the observer takes
/// every container's events (`object: nil`). Otto has exactly one mirrored
/// store, which is what makes that sound.
public final class CloudKitEventMonitor: SyncEventSource, Sendable {
    public let events: AsyncStream<SyncEvent>

    private let center: NotificationCenter
    private let observer: ObserverToken

    public init(center: NotificationCenter = .default) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: SyncEvent.self, bufferingPolicy: .bufferingNewest(128)
        )
        self.events = stream
        self.center = center
        self.observer = ObserverToken(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  let kind = Self.kind(of: event.type)
            else { return }
            continuation.yield(SyncEvent(kind: kind, phase: Self.phase(
                endDate: event.endDate, succeeded: event.succeeded, error: event.error
            )))
        })
    }

    deinit {
        center.removeObserver(observer.value)
    }

    static func kind(of type: NSPersistentCloudKitContainer.EventType) -> SyncEvent.Kind? {
        switch type {
        case .setup: .setup
        case .import: .import
        case .export: .export
        // A kind this build has never heard of has no consumer to reach.
        @unknown default: nil
        }
    }

    /// The framework posts one event twice: once with no end date, and again
    /// with one, when `succeeded` starts to mean something.
    static func phase(endDate: Date?, succeeded: Bool, error: (any Error)?) -> SyncEvent.Phase {
        guard endDate != nil else { return .started }
        if succeeded { return .succeeded }
        return .failed(failure(from: error))
    }

    static let noAccountSetupErrorCode = 134_400

    /// What failed, as far as the event can say.
    ///
    /// **The event carries a domain and a code, nothing else.** The framework
    /// rebuilds `error` from those two columns of its event table, so its
    /// `userInfo` is empty: read off a real full iCloud, whose records each
    /// failed `quotaExceeded` while the event reported bare `partialFailure`.
    /// So the per-record reasons a `CKError` normally carries cannot be read
    /// here, and `.partial` says only what is known.
    static func failure(from error: (any Error)?) -> SyncFailure {
        guard let error else { return .other(code: 0) }
        let nsError = error as NSError
        // Not a `CKError`: the framework's own report that setup found no
        // account. Read from `ANSCKEVENT` on a signed-out simulator; it has no
        // public constant.
        if nsError.domain == NSCocoaErrorDomain, nsError.code == noAccountSetupErrorCode {
            return .accountUnavailable
        }
        guard nsError.domain == CKError.errorDomain else { return .other(code: nsError.code) }
        switch CKError.Code(rawValue: nsError.code) {
        case .notAuthenticated, .accountTemporarilyUnavailable, .managedAccountRestricted, .badContainer:
            return .accountUnavailable
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .partialFailure:
            return .partial
        default:
            return .other(code: nsError.code)
        }
    }

    /// The token `addObserver` returns is not declared `Sendable`. It is only
    /// ever handed back to the center that minted it, from `deinit`.
    private struct ObserverToken: @unchecked Sendable {
        let value: any NSObjectProtocol

        init(_ value: any NSObjectProtocol) {
            self.value = value
        }
    }
}
