#if DEBUG
import SwiftUI
import OttoDomain
import OttoStores

// Previews for every Wave 3 view, all rendered against the fixture set that
// includes the awkward cases: a 31-anchored subscription, a trial two days from
// conversion, a paused subscription, and subscriptions with no payment method.

#Preview("Root") {
    RootView()
        .environment(PreviewData.model())
}

#Preview("Today") {
    TodayView()
        .environment(PreviewData.model())
}

#Preview("Today - dark, large type") {
    TodayView()
        .environment(PreviewData.model())
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Subscriptions") {
    SubscriptionsView()
        .environment(PreviewData.model())
}

#Preview("Subscriptions - largest type") {
    SubscriptionsView()
        .environment(PreviewData.model())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Detail - 31-anchored with ledger") {
    NavigationStack {
        SubscriptionDetailView(
            subscriptionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        )
    }
    .environment(PreviewData.model())
}

#Preview("Detail - trial near conversion") {
    NavigationStack {
        SubscriptionDetailView(
            subscriptionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
        )
    }
    .environment(PreviewData.model())
}

#Preview("Detail - cancelled, watching") {
    NavigationStack {
        SubscriptionDetailView(
            subscriptionID: UUID(uuidString: "00000000-0000-0000-0000-000000000004") ?? UUID()
        )
    }
    .environment(PreviewData.model())
}

#Preview("Add") {
    AddEditSubscriptionView(form: SubscriptionFormModel(
        dates: .fixed(today: PreviewData.today, now: PreviewData.now)
    ))
    .environment(PreviewData.model())
}

#Preview("Add - dark") {
    AddEditSubscriptionView(form: SubscriptionFormModel(
        dates: .fixed(today: PreviewData.today, now: PreviewData.now)
    ))
    .environment(PreviewData.model())
    .preferredColorScheme(.dark)
}
#endif
