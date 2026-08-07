import SwiftUI
import OttoStores

/// The app's top level: two tabs, Today and Subscriptions. Later waves add more;
/// two is what Wave 3 has screens for.
public struct RootView: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        TabView {
            Tab(String(localized: "Today"), systemImage: "sun.max") {
                TodayView()
            }
            Tab(String(localized: "Subscriptions"), systemImage: "creditcard") {
                SubscriptionsView()
            }
        }
        // A notification tap or action follow-up lands here: the detail opens
        // over whatever tab was up, without any notification logic in a view.
        .sheet(item: $model.requestedSubscriptionID.presentable) { requested in
            NavigationStack {
                SubscriptionDetailView(subscriptionID: requested.id)
            }
        }
    }
}

/// `UUID?` with the `Identifiable` shape `.sheet(item:)` needs.
private struct PresentedSubscription: Identifiable {
    let id: UUID
}

extension Binding where Value == UUID? {
    fileprivate var presentable: Binding<PresentedSubscription?> {
        Binding<PresentedSubscription?>(
            get: { wrappedValue.map(PresentedSubscription.init) },
            set: { wrappedValue = $0?.id }
        )
    }
}
