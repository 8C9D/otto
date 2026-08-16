import OttoDomain
import OttoPersistence
import OttoServices
import OttoStores
import OttoUI
import SwiftUI

// The composition root - the ONE place that names a concrete persistence type.
// Everything below the root sees repository protocols and domain values, so the
// Wave 6 CloudKit swap happens here and nowhere else. Wave 4 adds the second
// concrete assembly: the notification engine and its lifecycle triggers.
@main
struct OttoApp: App {
    /// Building the container can fail (disk, migration); the result is carried
    /// explicitly rather than crashing the launch or pretending it worked.
    private let bootstrap: Result<AppModel, any Error>
    private let coordinator: NotificationCoordinator?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let assembled = try Self.assemble()
            coordinator = assembled.coordinator
            bootstrap = .success(assembled.model)
        } catch {
            coordinator = nil
            bootstrap = .failure(error)
        }
    }

    private static func assemble() throws -> (model: AppModel, coordinator: NotificationCoordinator) {
        let containers = try OttoContainerFactory.localContainers()
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
            dates: dates
        )

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
            }
        }
    }
}
