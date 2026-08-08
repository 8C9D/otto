import SwiftUI
import OttoDomain
import OttoStores

/// The full list (spec §7.1 item 2): sortable, filterable, and every row shows the
/// monthly-equivalent cost so a $120/yr and a $10/mo compare at a glance.
struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @State private var listModel: SubscriptionListModel
    @State private var isAdding = false
    @State private var pendingDelete: Subscription?
    @State private var deleteFailure: String?

    /// The list model is injectable so the render suite can drive the status
    /// filter and observe the clear-filter action (Wave 10, defect J - the
    /// filtered empty state shipped unrendered because nothing could reach
    /// this state from a test). The app takes the default.
    init(listModel: SubscriptionListModel = SubscriptionListModel()) {
        _listModel = State(initialValue: listModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Subscriptions"))
                .toolbar { toolbarContent }
                .navigationDestination(for: SubscriptionListModel.Row.self) { row in
                    SubscriptionDetailView(subscriptionID: row.subscription.id)
                }
        }
        .task { await model.subscriptionsStore.refresh() }
        .sheet(isPresented: $isAdding) {
            AddEditSubscriptionView(form: model.formModel())
        }
        .confirmationDialog(
            String(localized: "Delete this subscription?"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let subscription = pendingDelete {
                    Task { await delete(subscription) }
                }
            }
        } message: {
            Text(String(localized: "Its history is kept and it stops appearing everywhere."))
        }
        .alert(
            String(localized: "Couldn't delete"),
            isPresented: Binding(
                get: { deleteFailure != nil },
                set: { if !$0 { deleteFailure = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(deleteFailure ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        let store = model.subscriptionsStore
        switch store.subscriptions {
        case .loading:
            ProgressView(String(localized: "Loading…"))
        case .failed(let error):
            LoadFailedView(error: error) { await store.refresh() }
        case .loaded(let subscriptions) where subscriptions.isEmpty:
            ContentUnavailableView {
                Label(String(localized: "No subscriptions yet"), systemImage: "creditcard")
            } description: {
                Text(String(localized: "Everything you add appears here."))
            } actions: {
                Button(String(localized: "Add Subscription")) { isAdding = true }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let subscriptions):
            list(subscriptions)
        }
    }

    @ViewBuilder
    private func list(_ subscriptions: [Subscription]) -> some View {
        let rows = listModel.rows(
            subscriptions: subscriptions,
            cancellations: model.subscriptionsStore.cancellations,
            today: model.subscriptionsStore.today
        )
        if rows.isEmpty, let filter = listModel.statusFilter {
            // §7.1: say so plainly rather than showing a blank list - the
            // unfiltered empty case always had this; the filtered one rendered
            // nothing at all (Wave 10, defect J).
            ContentUnavailableView {
                Label(
                    String(localized: "No \(statusText(filter)) subscriptions"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } description: {
                Text(String(localized: "Nothing matches this status filter."))
            } actions: {
                Button(String(localized: "Show All Statuses")) {
                    listModel.statusFilter = nil
                }
            }
        } else {
            List {
                ForEach(rows) { row in
                    NavigationLink(value: row) {
                        SubscriptionRowView(row: row)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) {
                            pendingDelete = row.subscription
                        }
                    }
                }
            }
            .refreshable { await model.subscriptionsStore.refresh() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(String(localized: "Add Subscription"), systemImage: "plus") {
                isAdding = true
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            sortAndFilterMenu
        }
    }

    private var sortAndFilterMenu: some View {
        @Bindable var listModel = listModel
        return Menu(String(localized: "Sort and Filter"), systemImage: "arrow.up.arrow.down") {
            Picker(String(localized: "Sort by"), selection: $listModel.sortOrder) {
                Text(String(localized: "Next date")).tag(SubscriptionListModel.SortOrder.nextDate)
                Text(String(localized: "Cost")).tag(SubscriptionListModel.SortOrder.cost)
                Text(String(localized: "Name")).tag(SubscriptionListModel.SortOrder.name)
                Text(String(localized: "Category")).tag(SubscriptionListModel.SortOrder.category)
            }
            Picker(String(localized: "Status"), selection: $listModel.statusFilter) {
                Text(String(localized: "All statuses")).tag(SubscriptionStatus?.none)
                Text(String(localized: "Trial")).tag(SubscriptionStatus?.some(.trial))
                Text(String(localized: "Active")).tag(SubscriptionStatus?.some(.active))
                Text(String(localized: "Paused")).tag(SubscriptionStatus?.some(.paused))
                Text(String(localized: "Cancelling")).tag(SubscriptionStatus?.some(.cancellationPending))
                Text(String(localized: "Cancelled")).tag(SubscriptionStatus?.some(.cancelled))
                Text(String(localized: "Archived")).tag(SubscriptionStatus?.some(.archived))
            }
        }
    }

    private func delete(_ subscription: Subscription) async {
        do {
            try await model.subscriptionsStore.delete(subscriptionID: subscription.id)
        } catch {
            deleteFailure = error.localizedDescription
        }
    }
}

/// One list row: name and status on the left, the real price and its
/// monthly equivalent on the right.
struct SubscriptionRowView: View {
    let row: SubscriptionListModel.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.subscription.name)
                    .font(.headline)
                StatusBadge(status: row.effectiveStatus)
                if let nextDate = row.nextDate {
                    Text(String(localized: "Next: \(nextDate.displayText())"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(currencyText(cents: row.subscription.amountCents, currencyCode: row.subscription.currencyCode))
                    .font(.body.monospacedDigit())
                Text(perMonthText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var perMonthText: String {
        let equivalent = currencyText(
            cents: row.monthlyEquivalentCents, currencyCode: row.subscription.currencyCode
        )
        return String(localized: "\(equivalent)/mo")
    }

    /// Spoken form: the row's meaning without relying on visual layout. The
    /// status is spoken too - the badge is the only visual carrier, and a
    /// custom label REPLACES the combined children, so leaving it out silenced
    /// "Trial" and "Paused" entirely (found and fixed in Wave 8's pass).
    var accessibilityText: String {
        let price = currencyText(cents: row.subscription.amountCents, currencyCode: row.subscription.currencyCode)
        let cadence = cycleText(row.subscription.cycle)
        let monthly = currencyText(cents: row.monthlyEquivalentCents, currencyCode: row.subscription.currencyCode)
        var parts = [
            row.subscription.name,
            statusText(row.effectiveStatus),
            "\(price) \(cadence)",
            String(localized: "\(monthly) a month")
        ]
        if let nextDate = row.nextDate {
            parts.append(String(localized: "next date \(nextDate.displayText())"))
        }
        return parts.joined(separator: ", ")
    }
}
