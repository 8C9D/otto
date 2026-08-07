import SwiftUI
import OttoDomain
import OttoStores

/// The home screen (spec §7.1 item 1): Needs action, Next 30 days, Later.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Today"))
                .navigationDestination(for: TodayEntry.self) { entry in
                    SubscriptionDetailView(subscriptionID: entry.subscription.id)
                }
        }
        .task { await model.subscriptionsStore.refresh() }
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
            ContentUnavailableView(
                String(localized: "No subscriptions yet"),
                systemImage: "creditcard",
                description: Text(String(localized: "Add the ones you pay for from the Subscriptions tab."))
            )
        case .loaded:
            if let overview = store.overview {
                overviewList(overview)
            }
        }
    }

    private func overviewList(_ overview: TodayOverview) -> some View {
        List {
            Section(String(localized: "Needs action")) {
                if overview.needsAction.isEmpty {
                    // Spec §7.1: when empty, say so plainly - never a blank section.
                    Text(String(localized: "Nothing needs your attention."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(overview.needsAction) { entry in
                        NavigationLink(value: entry) { TodayEntryRow(entry: entry) }
                    }
                }
            }
            if !overview.next30Days.isEmpty {
                Section(String(localized: "Next 30 days")) {
                    ForEach(overview.next30Days) { entry in
                        NavigationLink(value: entry) { TodayEntryRow(entry: entry) }
                    }
                }
            }
            if !overview.later.isEmpty {
                Section(String(localized: "Later")) {
                    ForEach(overview.later) { entry in
                        NavigationLink(value: entry) { TodayEntryRow(entry: entry) }
                    }
                }
            }
        }
        .refreshable { await model.subscriptionsStore.refresh() }
    }
}

/// One Today card: what it is, why it is here, and when.
struct TodayEntryRow: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.subscription.name)
                    .font(.headline)
                Spacer()
                if let amountText {
                    Text(amountText)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Label(reasonText, systemImage: symbolName)
                .font(.subheadline)
                .foregroundStyle(entry.needsAction ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var amountText: String? {
        switch entry.reason {
        case .upcomingCharge(let amountCents), .trialConverts(let amountCents),
             .trialConverted(let amountCents):
            currencyText(cents: amountCents, currencyCode: entry.subscription.currencyCode)
        case .trialActionNeeded, .verificationDue, .verificationFailed, .needsReview,
             .pauseResumes, .verificationCheck:
            nil
        }
    }

    private var reasonText: String {
        let date = entry.date.displayText()
        return switch entry.reason {
        case .trialActionNeeded:
            String(localized: "Trial - cancel by \(date)")
        case .trialConverted:
            // A statement of fact, not a request to act (spec §5.2a): the trial
            // converted and money is moving.
            String(localized: "Trial converted \(date) - you're now being charged")
        case .verificationDue:
            String(localized: "Cancelled - check that the charges stopped")
        case .verificationFailed:
            String(localized: "Still charging after cancellation")
        case .needsReview:
            String(localized: "Marked cancelled, but nothing is watching it - review this")
        case .upcomingCharge:
            String(localized: "Charges \(date)")
        case .trialConverts:
            String(localized: "Trial converts \(date)")
        case .pauseResumes:
            String(localized: "Resumes billing \(date)")
        case .verificationCheck:
            String(localized: "Verification check \(date)")
        }
    }

    private var symbolName: String {
        switch entry.reason {
        case .trialActionNeeded: "hourglass"
        case .trialConverted: "dollarsign.circle"
        case .verificationDue: "questionmark.circle"
        case .verificationFailed: "exclamationmark.triangle"
        case .needsReview: "exclamationmark.triangle"
        case .upcomingCharge: "calendar"
        case .trialConverts: "hourglass"
        case .pauseResumes: "play.circle"
        case .verificationCheck: "eye"
        }
    }
}
