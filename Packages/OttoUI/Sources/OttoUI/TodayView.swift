import SwiftUI
import OttoDomain
import OttoServices
import OttoStores

/// The home screen (spec §7.1 item 1): Needs action, Next 30 days, Later.
/// Which sections it composes is decided in `TodaySectionPlan.swift`.
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
        .task {
            await model.subscriptionsStore.refresh()
            await model.notifications?.refreshPermission()
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
        case .loaded(let subscriptions):
            // The empty database routes through the SAME list as a populated
            // one (Wave 9A defect 1): a bare placeholder here swallowed the
            // §6-constraint-3 permission surface exactly on first launch.
            if let overview = store.overview {
                overviewList(overview, subscriptionsEmpty: subscriptions.isEmpty)
            }
        }
    }

    private func overviewList(_ overview: TodayOverview, subscriptionsEmpty: Bool) -> some View {
        let sections = TodaySection.plan(TodaySection.input(
            model: model, overview: overview, subscriptionsEmpty: subscriptionsEmpty
        ))
        return List {
            ForEach(sections, id: \.self) { section in
                self.section(section, overview: overview)
            }
        }
        .refreshable { await model.subscriptionsStore.refresh() }
    }

    @ViewBuilder
    private func section(_ section: TodaySection, overview: TodayOverview) -> some View {
        switch section {
        case .notificationStatus:
            // An app whose entire value is notifications must not fail silently
            // when it can't send them: denied is loud, at the top, permanently
            // (Wave 4 constraint 3).
            if let notifications = model.notifications {
                notificationStatusSection(notifications)
            }
        case .unreadableRecords:
            unreadableRecordsSection(count: model.subscriptionsStore.unreadableCount)
        case .readRepairs:
            readRepairsSection(model.subscriptionsStore.readRepairs)
        case .noSubscriptionsYet:
            noSubscriptionsSection
        case .needsAction:
            needsActionSection(overview.needsAction)
        case .next30Days:
            entriesSection(String(localized: "Next 30 days"), entries: overview.next30Days)
        case .later:
            entriesSection(String(localized: "Later"), entries: overview.later)
        case .coverage:
            coverageSection
        case .coverageGap:
            coverageGapSection
        }
    }

    private var noSubscriptionsSection: some View {
        Section {
            ContentUnavailableView(
                String(localized: "No subscriptions yet"),
                systemImage: "creditcard",
                description: Text(String(localized: "Add the ones you pay for from the Subscriptions tab."))
            )
            .listRowBackground(Color.clear)
        }
    }

    private func needsActionSection(_ entries: [TodayEntry]) -> some View {
        Section(String(localized: "Needs action")) {
            if entries.isEmpty {
                // Spec §7.1: when empty, say so plainly - never a blank section.
                Text(String(localized: "Nothing needs your attention."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    NavigationLink(value: entry) { TodayEntryRow(entry: entry) }
                }
            }
        }
    }

    private func entriesSection(_ title: String, entries: [TodayEntry]) -> some View {
        Section(title) {
            ForEach(entries) { entry in
                NavigationLink(value: entry) { TodayEntryRow(entry: entry) }
            }
        }
    }

    /// The horizon, stated honestly (spec §6.1 point 4): never let the user
    /// believe coverage extends further than it does.
    @ViewBuilder
    private var coverageSection: some View {
        if let outcome = model.notifications?.outcome {
            Section {
                EmptyView()
            } footer: {
                let coveredThrough = outcome.coveredThrough.displayText()
                Text(String(localized: "Reminders scheduled through \(coveredThrough)."))
            }
        }
    }

    private var coverageGapSection: some View {
        Section {
            CoverageGapCard(failureCount: model.notifications?.outcome?.ledgerFailures.count ?? 0)
        }
    }

    /// Spec §5.2b (v1.4): unmappable records surface as ONE aggregate
    /// needs-review card, never one per record, and never silently.
    @ViewBuilder
    private func unreadableRecordsSection(count: Int) -> some View {
        if count > 0 {
            Section(String(localized: "Needs review")) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "\(subscriptionCountText(count)) couldn't be read"))
                            .font(.headline)
                        Text(String(localized: "The records exist but Otto can't display them. Nothing was deleted."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Spec §4a (Wave 6B-Prep): reads that repaired a two-device shape surface
    /// as ONE aggregate card, like unreadable records - a repair decided
    /// something (which pause episode survived, that a term is still missing),
    /// and the user must see that it happened rather than wonder.
    @ViewBuilder
    private func readRepairsSection(_ reports: [SubscriptionReadRepairReport]) -> some View {
        if !reports.isEmpty {
            Section(String(localized: "Needs review")) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "\(subscriptionCountText(reports.count)) repaired on read"))
                            .font(.headline)
                        Text(reports.map(\.name).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Conflicting copies were resolved the same way on every device. Nothing was deleted."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func notificationStatusSection(_ notifications: NotificationStatusStore) -> some View {
        switch notifications.permission {
        case .denied:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Notifications are off"))
                            .font(.headline)
                        Text(String(
                            localized: "Otto exists to warn you before money moves, and it can't. Turn notifications on in Settings."
                        ))
                            .font(.subheadline)
                    }
                } icon: {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityElement(children: .combine)
            }
        case .notDetermined:
            Section {
                Button {
                    Task { await notifications.requestPermission() }
                } label: {
                    Label(
                        String(localized: "Turn on reminders - they're the whole point"),
                        systemImage: "bell.badge"
                    )
                }
            }
        case .provisional:
            Section {
                Label(
                    String(localized: "Reminders deliver quietly - they won't break through Focus. Allow full notifications in Settings."),
                    systemImage: "bell"
                )
                .font(.subheadline)
            }
        case .authorized:
            EmptyView()
        }
    }
}

/// One Today card: what it is, why it is here, and when.
/// The coverage sentence's counterpart, in the aggregate-card shape
/// `unreadableRecordsSection` established: say that reminders could not be
/// updated, and how many subscriptions it touched.
///
/// A count and nothing else. Naming the vendors would put subscription content
/// on a screen readable at a glance, and the user does not need it to know
/// something is wrong - `ledgerFailures` carries only UUIDs anyway.
///
/// Its own `View` rather than a method on `TodayView`, following `TodayEntryRow`:
/// a private `@ViewBuilder` that reads `model` cannot be rendered by a test, and
/// this card is new copy that has to be seen to be believed.
struct CoverageGapCard: View {
    /// Zero when the whole pass failed, so there is no per-subscription count to
    /// give - a different sentence, because "0 subscriptions couldn't be
    /// updated" is not what happened.
    let failureCount: Int

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }

    /// Not private, for the same reason `InsightsView.monthText` is not: the
    /// choice BETWEEN the two wordings needs no accessibility tree to assert,
    /// and while it was private both could be swapped - rendering "0
    /// subscriptions couldn't be updated" for a whole failed pass - with every
    /// test on both the host and the simulator green.
    var headline: String {
        failureCount > 0
            ? String(localized: "\(subscriptionCountText(failureCount)) couldn't be updated")
            : String(localized: "Reminders couldn't be updated")
    }

    var detail: String {
        failureCount > 0
            ? String(localized: """
              Otto couldn't refresh their reminders on its last check, so some may be missing. \
              Nothing was deleted, and it will try again.
              """)
            : String(localized: """
              Otto's last check didn't finish, so some reminders may be missing. \
              Nothing was deleted, and it will try again.
              """)
    }
}

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
             .pauseResumes, .verificationCheck, .verificationNeedsResumeDate:
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
        case .verificationNeedsResumeDate:
            String(localized: "Cancelled while paused - when was billing due to resume?")
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
        case .verificationNeedsResumeDate: "calendar.badge.exclamationmark"
        case .upcomingCharge: "calendar"
        case .trialConverts: "hourglass"
        case .pauseResumes: "play.circle"
        case .verificationCheck: "eye"
        }
    }
}
