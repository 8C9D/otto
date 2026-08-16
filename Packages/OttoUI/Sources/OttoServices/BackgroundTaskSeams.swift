#if os(iOS)
import BackgroundTasks
import Foundation

// The two seams over the `BGTaskScheduler` boundary, split out of
// `NotificationCoordinator.swift` when the registration seam pushed it past
// SwiftLint's 400-line file_length. Both sit at the SYSTEM boundary, per the
// rule recorded at `LiveNotificationClient.swift` - a seam a fake cannot
// implement tests nothing, and a seam above the logic mocks the logic away.

/// The two calls the background-refresh handler makes on its task.
///
/// `BGAppRefreshTask` has no public initializer, so without this seam the whole
/// background path - the pass, the completion latch, the expiration race, and
/// whether the outcome is published at all - is reachable only from the OS.
/// That is R4-2: the coordinator is inside `#if os(iOS)` and compiles to
/// nothing under host `swift test`, and even on a simulator there was nothing a
/// test could hand it. The seam is at the system boundary, not above the
/// handler, so a fake cannot mock away the logic under test.
public protocol BackgroundRefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: BackgroundRefreshTask {}

/// The one call `start()` makes on `BGTaskScheduler.shared` (round 5, item 10:
/// N3-6b). The registration was inline on the bare singleton, so no test could
/// assert the task was ever registered, let alone under the Info.plist
/// identifier. The signature is the framework's own - the seam sits at the
/// system boundary, and a fake records the identifier and captures the launch
/// handler without mocking anything away.
///
/// The handler still takes the framework's `BGTask`, deliberately: narrowing it
/// to `BackgroundRefreshTask` would move the `BGAppRefreshTask` downcast out of
/// the launch closure and into the conforming extension, which is exactly the
/// logic-behind-the-seam shape the `LiveNotificationClient` doctrine forbids.
/// The cost is that `BGTask` has no public initializer, so the launch closure's
/// body stays reachable only by the OS - stated as this item's residual floor.
public protocol BackgroundTaskRegistering {
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool
}

extension BGTaskScheduler: BackgroundTaskRegistering {}
#endif
