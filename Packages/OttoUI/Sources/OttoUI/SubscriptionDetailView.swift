import SwiftUI
import OttoDomain
import OttoStores

/// Detail (spec §7.1 item 4): status, next charge, the billing-event ledger,
/// price history as a plain list (the chart is Wave 7), and cancellation info.
struct SubscriptionDetailView: View {
    let subscriptionID: UUID
    @Environment(AppModel.self) private var model
    @State private var store: SubscriptionDetailStore?
    @State private var isEditing = false

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView(String(localized: "Loading…"))
            }
        }
        .task {
            if store == nil {
                store = model.detailStore(for: subscriptionID)
            }
            await store?.refresh()
        }
        .sheet(isPresented: $isEditing) {
            // Reload after an edit, whether saved or abandoned - refresh is cheap
            // and the subscription may have changed.
            Task { await store?.refresh() }
        } content: {
            if let subscription = store?.state.value?.subscription {
                AddEditSubscriptionView(form: model.formModel(editing: subscription))
            }
        }
    }

    @ViewBuilder
    private func content(_ store: SubscriptionDetailStore) -> some View {
        switch store.state {
        case .loading:
            ProgressView(String(localized: "Loading…"))
        case .failed(let error):
            if case SubscriptionDetailStore.DetailError.subscriptionNotFound = error {
                ContentUnavailableView(
                    String(localized: "This subscription was deleted"),
                    systemImage: "trash"
                )
            } else {
                LoadFailedView(error: error) { await store.refresh() }
            }
        case .loaded(let detail):
            detailList(detail)
                .navigationTitle(detail.subscription.name)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "Edit")) { isEditing = true }
                    }
                }
        }
    }

    private func detailList(_ detail: SubscriptionDetail) -> some View {
        List {
            overviewSection(detail)
            trialSection(detail)
            cancellationSection(detail)
            ledgerSection(detail)
            priceHistorySection(detail)
        }
        .refreshable { await store?.refresh() }
    }

    // MARK: - Sections

    private func overviewSection(_ detail: SubscriptionDetail) -> some View {
        let subscription = detail.subscription
        return Section {
            LabeledContent(String(localized: "Status")) {
                StatusBadge(status: subscription.status)
            }
            LabeledContent(
                String(localized: "Price"),
                value: currencyText(cents: subscription.amountCents, currencyCode: subscription.currencyCode)
            )
            LabeledContent(String(localized: "Cycle"), value: cycleText(subscription.cycle))
            LabeledContent(
                String(localized: "Monthly equivalent"),
                value: monthlyEquivalentText(
                    amountCents: subscription.amountCents,
                    cycle: subscription.cycle,
                    currencyCode: subscription.currencyCode
                )
            )
            LabeledContent(String(localized: "Category"), value: categoryText(subscription.category))
            if let entry = todayEntry(
                for: subscription, cancellation: detail.cancellation, from: model.subscriptionsStore.today
            ) {
                LabeledContent(nextDateLabel(entry), value: entry.date.displayText())
            }
            if subscription.status == .paused, let resumes = subscription.pauseEndsOn {
                LabeledContent(String(localized: "Resumes"), value: resumes.displayText())
            }
            LabeledContent(
                String(localized: "Payment method"),
                value: detail.paymentMethod?.label ?? String(localized: "None recorded")
            )
            if let notes = subscription.notes {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nextDateLabel(_ entry: TodayEntry) -> String {
        switch entry.reason {
        case .upcomingCharge: String(localized: "Next charge")
        case .trialConverts, .trialActionNeeded: String(localized: "Trial converts")
        case .trialConverted: String(localized: "Trial converted")
        case .pauseResumes: String(localized: "Resumes")
        case .verificationDue, .verificationFailed, .verificationCheck: String(localized: "Verification check")
        case .needsReview: String(localized: "Needs review")
        }
    }

    @ViewBuilder
    private func trialSection(_ detail: SubscriptionDetail) -> some View {
        if let trial = detail.subscription.trial {
            Section(String(localized: "Trial")) {
                LabeledContent(String(localized: "Started"), value: trial.startDate.displayText())
                LabeledContent(
                    String(localized: "Length"),
                    value: String(localized: "\(trial.lengthDays) days")
                )
                LabeledContent(String(localized: "Cancel by"), value: trial.cancelByDate.displayText())
                LabeledContent(String(localized: "Converts"), value: trial.conversionDate.displayText())
                LabeledContent(
                    String(localized: "Then charges"),
                    value: currencyText(
                        cents: trial.convertsToAmountCents,
                        currencyCode: detail.subscription.currencyCode
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func cancellationSection(_ detail: SubscriptionDetail) -> some View {
        Section {
            if let record = detail.cancellation {
                LabeledContent(
                    String(localized: "Marked cancelled"),
                    value: record.markedCancelledAt.formatted(date: .abbreviated, time: .omitted)
                )
                LabeledContent(
                    String(localized: "Watching for a charge on"),
                    value: record.nextChargeDateIfNotCancelled.displayText()
                )
                LabeledContent(String(localized: "Verification")) {
                    verificationBadge(record.verificationState)
                }
                if let note = record.evidenceNote {
                    LabeledContent(String(localized: "Evidence"), value: note)
                }
            }
            if let url = detail.subscription.cancellationURL {
                Link(destination: url) {
                    Label(String(localized: "Open cancellation page"), systemImage: "safari")
                }
            }
            if let notes = detail.subscription.cancellationNotes {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if detail.cancellation == nil {
                // The guided flow - mark cancelling, capture evidence, schedule
                // the verification - is Wave 5; the entry point is stubbed so the
                // screen's shape is honest about what is coming.
                Button(String(localized: "Mark as cancelling…")) {}
                    .disabled(true)
            }
        } header: {
            Text(String(localized: "Cancelling"))
        } footer: {
            if detail.cancellation == nil {
                Text(String(localized: "The guided cancellation flow arrives in a later update."))
            }
        }
    }

    private func verificationBadge(_ state: CancellationRecord.VerificationState) -> some View {
        let badge: BadgeSpec = switch state {
        case .pending:
            BadgeSpec(text: String(localized: "Waiting"), symbolName: "clock", color: .orange)
        case .verifiedStopped:
            BadgeSpec(text: String(localized: "Charges stopped"), symbolName: "checkmark.circle", color: .green)
        case .stillCharging:
            BadgeSpec(text: String(localized: "Still charging"), symbolName: "exclamationmark.triangle", color: .red)
        case .needsManualReview:
            BadgeSpec(text: String(localized: "Needs review"), symbolName: "exclamationmark.triangle", color: .red)
        }
        return badge.label
    }

    @ViewBuilder
    private func ledgerSection(_ detail: SubscriptionDetail) -> some View {
        Section(String(localized: "Expected charges")) {
            if detail.events.isEmpty {
                Text(String(localized: "No charges recorded yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.events) { event in
                    BillingEventRow(event: event, currencyCode: detail.subscription.currencyCode)
                }
            }
        }
    }

    @ViewBuilder
    private func priceHistorySection(_ detail: SubscriptionDetail) -> some View {
        if !detail.priceHistory.isEmpty {
            Section(String(localized: "Price history")) {
                ForEach(detail.priceHistory) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(change.effectiveDate.displayText())
                            Spacer()
                            Text(priceChangeText(change, currencyCode: detail.subscription.currencyCode))
                                .font(.body.monospacedDigit())
                        }
                        if let note = change.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func priceChangeText(_ change: PriceChange, currencyCode: String) -> String {
        let old = currencyText(cents: change.oldAmountCents, currencyCode: currencyCode)
        let new = currencyText(cents: change.newAmountCents, currencyCode: currencyCode)
        return String(localized: "\(old) to \(new)")
    }
}

/// A small state badge: text and symbol always carry the meaning, colour only
/// reinforces it.
private struct BadgeSpec {
    let text: String
    let symbolName: String
    let color: Color

    var label: some View {
        Label(text, systemImage: symbolName)
            .foregroundStyle(color)
    }
}

/// One ledger row: the expected date and amount, and what became of it.
struct BillingEventRow: View {
    let event: BillingEvent
    let currencyCode: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.expectedDate.displayText())
                stateLabel
                    .font(.caption)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(currencyText(cents: event.expectedAmountCents, currencyCode: currencyCode))
                    .font(.body.monospacedDigit())
                if let actual = event.actualAmountCents, actual != event.expectedAmountCents {
                    Text(String(localized: "charged \(currencyText(cents: actual, currencyCode: currencyCode))"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var stateLabel: some View {
        let badge: BadgeSpec = switch event.state {
        case .upcoming:
            BadgeSpec(text: String(localized: "Expected"), symbolName: "calendar", color: .gray)
        case .confirmedCharged:
            BadgeSpec(text: String(localized: "Charged"), symbolName: "checkmark.circle", color: .green)
        case .confirmedNotCharged:
            BadgeSpec(text: String(localized: "Not charged"), symbolName: "xmark.circle", color: .gray)
        case .unexpectedCharge:
            BadgeSpec(text: String(localized: "Unexpected charge"), symbolName: "exclamationmark.triangle", color: .red)
        case .skipped:
            BadgeSpec(text: String(localized: "Skipped"), symbolName: "arrow.right.circle", color: .gray)
        }
        return badge.label
    }
}
