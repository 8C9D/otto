import SwiftUI
import OttoStores

/// The app's top level: two tabs, Today and Subscriptions. Later waves add more;
/// two is what Wave 3 has screens for.
public struct RootView: View {
    public init() {}

    public var body: some View {
        TabView {
            Tab(String(localized: "Today"), systemImage: "sun.max") {
                TodayView()
            }
            Tab(String(localized: "Subscriptions"), systemImage: "creditcard") {
                SubscriptionsView()
            }
        }
    }
}
