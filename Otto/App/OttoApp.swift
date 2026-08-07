import OttoPersistence
import OttoStores
import OttoUI
import SwiftUI

// The composition root - the ONE place that names a concrete persistence type.
// Everything below the root sees repository protocols and domain values, so the
// Wave 6 CloudKit swap happens here and nowhere else.
@main
struct OttoApp: App {
    /// Building the container can fail (disk, migration); the result is carried
    /// explicitly rather than crashing the launch or pretending it worked.
    private let bootstrap: Result<AppModel, any Error>

    init() {
        do {
            let container = try OttoContainerFactory.localContainer()
            let store = OttoStore(modelContainer: container)
            bootstrap = .success(AppModel(repositories: AppModel.Repositories(
                subscriptions: store,
                billingEvents: store,
                cancellations: store,
                priceChanges: store,
                paymentMethods: store
            )))
        } catch {
            bootstrap = .failure(error)
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
    }
}
