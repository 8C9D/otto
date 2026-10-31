import OttoDomain
import OttoPersistence
import OttoRepositories
import OttoServices
import OttoStores
import OttoUI
import SwiftUI

// The composition root - the ONE place that names a concrete persistence type.
// Everything below the root sees repository protocols and domain values, so
// CloudKit is chosen here and nowhere else. Wave 4 adds the second concrete
// assembly: the notification engine and its lifecycle triggers.
@main
struct OttoApp: App {
    /// Building the container can fail (disk, migration); the result is carried
    /// explicitly rather than crashing the launch or pretending it worked.
    private let bootstrap: Result<AppModel, any Error>
    private let coordinator: NotificationCoordinator?
    private let sync: SyncStatusStore?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let assembled = try Self.assemble()
            coordinator = assembled.coordinator
            sync = assembled.model.sync
            bootstrap = .success(assembled.model)
        } catch {
            coordinator = nil
            sync = nil
            bootstrap = .failure(error)
        }
    }

    private static func assemble() throws -> (model: AppModel, coordinator: NotificationCoordinator) {
        let cloudContainer = cloudContainerIdentifier
        try initializeCloudKitSchemaIfAsked(cloudContainer: cloudContainer)
        // Before the container opens: `setup` fires as a mirrored store loads.
        let syncEvents = CloudKitEventMonitor()
        let syncState = SyncState.load()
        let containers = try OttoContainerFactory.localContainers(
            syncState: syncState, cloudContainerIdentifier: cloudContainer
        )
        let store = OttoStore(containers: containers)
        let dates = DateProvider.live

        let client = LiveNotificationClient()
        // Fire times are read from settings on every pass, so the Wave 8
        // notification-time setting reaches background passes too.
        let fireTimes: @Sendable () -> FireTimePolicy = { SettingsStore.fireTimePolicy() }
        // N4-7: one gate, wrapped ONCE, handed to every consumer below - the
        // store, the coordinator and the action handler all reschedule through
        // the same instance, which is what serialises their passes. A second
        // wrap, or handing anyone the bare scheduler, reopens the overlap.
        let scheduler = CoalescingReminderScheduler(base: NotificationScheduler(
            subscriptions: store, cancellations: store, billingEvents: store, client: client,
            fireTimes: fireTimes
        ))
        let notifications = NotificationStatusStore(
            scheduler: scheduler, client: client, dates: dates
        )
        let sync = makeSyncStatus(
            store: store, containers: containers, syncState: syncState,
            cloudContainer: cloudContainer, dates: dates
        )
        let model = AppModel(
            repositories: AppModel.Repositories(
                subscriptions: store,
                billingEvents: store,
                cancellations: store,
                priceChanges: store,
                paymentMethods: store,
                transfer: store
            ),
            notifications: notifications,
            sync: sync,
            dates: dates
        )
        if containers.syncSessionMode == .mirrored {
            startConvergence(events: syncEvents.events, store: store, model: model, sync: sync, dates: dates)
        }

        let coordinator = NotificationCoordinator(
            scheduler: scheduler,
            handler: NotificationActionHandler(
                subscriptions: store,
                flows: model.flows,
                client: client,
                scheduler: scheduler,
                fireTimes: fireTimes
            ),
            client: client,
            now: dates.now,
            today: dates.today,
            timeZone: dates.timeZone
        )
        wire(coordinator, to: model, notifications: notifications)
        // BGTaskScheduler registration must complete before launch finishes.
        coordinator.start()
        return (model, coordinator)
    }

    /// Which CloudKit container this build syncs to, or nil when it doesn't.
    /// Set per configuration in `project.yml`: a Release stays off until its
    /// schema is deployed to production (`docs/sync-verification.md`).
    private static var cloudContainerIdentifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "OttoCloudKitContainer") as? String
        return value?.isEmpty == false ? value : nil
    }

    /// The one-time step before a production schema deploy
    /// (`docs/sync-verification.md`): launch a Debug build, signed into iCloud,
    /// with this argument. Compiled out of Release.
    private static func initializeCloudKitSchemaIfAsked(cloudContainer: String?) throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OttoInitializeCloudKitSchema"), let cloudContainer {
            try OttoContainerFactory.initializeCloudKitSchema(containerIdentifier: cloudContainer)
        }
        #endif
    }

    private static func makeSyncStatus(
        store: OttoStore,
        containers: OttoContainers,
        syncState: SyncState,
        cloudContainer: String?,
        dates: DateProvider
    ) -> SyncStatusStore {
        let cloud: any CloudSyncClient = cloudContainer.map(CloudKitSyncClient.init(containerIdentifier:))
            ?? UnavailableCloudSyncClient()
        return SyncStatusStore(
            activation: SyncActivationService(
                transfer: store, cloud: cloud, sessionMode: containers.syncSessionMode
            ),
            cloud: cloud,
            initialState: syncState,
            sessionMode: containers.syncSessionMode,
            isAvailable: cloudContainer != nil,
            mirroredOpenFailed: containers.mirroredOpenFailed,
            dates: dates
        )
    }

    /// Runs for the life of the process; the `Task` is what retains it.
    private static func startConvergence(
        events: AsyncStream<SyncEvent>,
        store: OttoStore,
        model: AppModel,
        sync: SyncStatusStore,
        dates: DateProvider
    ) {
        let convergence = SyncCoordinator(
            events: events,
            reconciliation: store,
            now: dates.now,
            afterConvergence: { [weak model] in await model?.syncDidConverge() },
            onActivity: { [weak sync] activity in await sync?.apply(activity) }
        )
        Task { await convergence.run() }
    }

    private static func wire(
        _ coordinator: NotificationCoordinator,
        to model: AppModel,
        notifications: NotificationStatusStore
    ) {
        // A nil outcome means the pass failed; the store drops its previous
        // one rather than letting Today keep stating that pass's coverage.
        coordinator.onOutcome = { [weak notifications] outcome in
            notifications?.apply(outcome)
        }
        coordinator.onFollowUp = { [weak model] followUp in
            switch followUp {
            case .openDetail(let subscriptionID):
                model?.requestedSubscriptionID = subscriptionID
            case .openCancellation(let subscriptionID, let url):
                model?.requestedSubscriptionID = subscriptionID
                if let url {
                    UIApplication.shared.open(url)
                }
            case .none:
                break
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let model):
                RootView()
                    .environment(model)
            case .failure(let error):
                ContentUnavailableView {
                    Label(String(localized: "Otto couldn't open its data"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The app-foreground reschedule trigger (spec §6.2).
            if phase == .active {
                coordinator?.appDidBecomeActive()
                // A sign-out happens in the Settings app, so returning here is
                // when this device can first find out.
                Task { await sync?.refreshAccount() }
            }
        }
    }
}
