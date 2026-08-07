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
    @State private var isCancelling = false
    @State private var isPausing = false
    @State private var actionFailure: String?

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
        .sheet(isPresented: $isCancelling) {
            Task { await store?.refresh() }
        } content: {
            if let subscription = store?.state.value?.subscription {
                CancellationFlowView(subscription: subscription)
            }
        }
        .sheet(isPresented: $isPausing) {
            Task { await store?.refresh() }
        } content: {
            if let subscription = store?.state.value?.subscription {
                PauseFlowView(subscription: subscription, today: model.subscriptionsStore.today)
            }
        }
        .alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(
                get: { actionFailure != nil },
                set: { if !$0 { actionFailure = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(actionFailure ?? "")
        }
    }

    /// Runs one flow action, surfacing a failure instead of swallowing it, and
    /// reloads the screen either way.
    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                actionFailure = error.localizedDescription
            }
            await store?.refresh()
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
            pauseSection(detail)
            CancellationSectionView(detail: detail, isCancelling: $isCancelling, perform: perform)
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
        case .verificationNeedsResumeDate: String(localized: "Needs a resume date")
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
                trialActions(detail, trial: trial)
            }
        }
    }

    /// The trial flow's two verbs - keep, or cancel (which hands off to the
    /// cancellation flow). A converted-unacknowledged trial gets the §5.2a
    /// confirmation instead: money is moving, and confirming records that the
    /// user knows - it deletes nothing.
    @ViewBuilder
    private func trialActions(_ detail: SubscriptionDetail, trial: TrialTerm) -> some View {
        let subscription = detail.subscription
        let today = model.subscriptionsStore.today
        if subscription.isConvertedTrial(asOf: today) {
            let converted = trial.conversionDate.displayText()
            let amount = currencyText(
                cents: trial.convertsToAmountCents, currencyCode: subscription.currencyCode
            )
            Text(String(localized: "This trial converted on \(converted). You're now being charged \(amount)."))
                .font(.callout)
                .foregroundStyle(.orange)
            Button(String(localized: "Got it - I'm keeping it")) {
                perform { try await model.confirmTrialConversion(subscriptionID: subscription.id) }
            }
            Button(String(localized: "I'm cancelling it…")) {
                isCancelling = true
            }
        } else if subscription.status == .trial {
            Button(String(localized: "Keeping it - stop the countdown reminders")) {
                perform { try await model.keepCurrentCharge(subscriptionID: subscription.id) }
            }
            Button(String(localized: "Cancel this trial…"), role: .destructive) {
                isCancelling = true
            }
        }
    }

    /// Pause and resume (spec §5.1): a paused subscription resumes here, an
    /// active one pauses through its own small flow. A pause whose end date has
    /// already passed is effectively active by derivation (spec §5.2a, v1.6);
    /// the row states that fact and offers to persist it - persistence is an
    /// optimisation, never the mechanism.
    @ViewBuilder
    private func pauseSection(_ detail: SubscriptionDetail) -> some View {
        let subscription = detail.subscription
        let today = model.subscriptionsStore.today
        if subscription.status == .paused {
            Section(String(localized: "Pause")) {
                if subscription.isResumedPause(asOf: today) {
                    let ended = subscription.pauseEndsOn.map { $0.displayText() } ?? ""
                    Text(String(localized: "This pause ended \(ended) - billing has resumed."))
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button(String(localized: "Got it - mark as active")) {
                        perform { try await model.resumeSubscription(subscriptionID: subscription.id) }
                    }
                } else {
                    if subscription.pauseEndsOn == nil {
                        Text(String(localized: """
                        Paused indefinitely. Otto is not watching for charges - resume \
                        when the vendor does, and it picks the schedule back up.
                        """))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button(String(localized: "Resume billing now")) {
                        perform { try await model.resumeSubscription(subscriptionID: subscription.id) }
                    }
                }
            }
        } else if subscription.effectiveStatus(asOf: today) == .active {
            Section(String(localized: "Pause")) {
                Button(String(localized: "Pause billing…")) {
                    isPausing = true
                }
            }
        }
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

/// The pause flow (spec §5.1): the vendor suspended billing - a gym freeze, a
/// seasonal hold - and Otto records it. The resume date is optional and honest:
/// with one, the resume is derived and the resumed charges are watched ahead of
/// time; without one, Otto freezes its bookkeeping and waits to be told.
private struct PauseFlowView: View {
    let subscription: Subscription
    let today: CalendarDay
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var knowsResumeDate: Bool
    @State private var resumeDate: CalendarDay
    @State private var failure: String?

    init(subscription: Subscription, today: CalendarDay) {
        self.subscription = subscription
        self.today = today
        _knowsResumeDate = State(initialValue: false)
        _resumeDate = State(initialValue: today.adding(days: 30))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: """
                    Pausing tells Otto the vendor has suspended billing. No charges \
                    are expected and no renewal reminders fire until it resumes.
                    """))
                        .font(.callout)
                }
                Section {
                    Toggle(String(localized: "I know when billing resumes"), isOn: $knowsResumeDate)
                    if knowsResumeDate {
                        DatePicker(
                            String(localized: "Billing resumes"),
                            selection: $resumeDate.asDate()
                        )
                        .datePickerStyle(.compact)
                    }
                } footer: {
                    if knowsResumeDate {
                        Text(String(localized: """
                        Otto warns you before this date and expects charges from it - \
                        even if the app never gets opened in between.
                        """))
                    } else {
                        Text(String(localized: """
                        Without a date, Otto stops watching entirely and waits for you \
                        to resume it here. If billing restarts unnoticed, the charges \
                        appear once you resume.
                        """))
                    }
                }
                Section {
                    Button(String(localized: "Pause billing")) {
                        Task { await pause() }
                    }
                }
            }
            .navigationTitle(String(localized: "Pausing \(subscription.name)"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Not yet")) { dismiss() }
                }
            }
            .alert(
                String(localized: "Couldn't pause it"),
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { failure = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func pause() async {
        do {
            try await model.pauseSubscription(
                subscriptionID: subscription.id,
                resumesOn: knowsResumeDate ? resumeDate : nil
            )
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A small state badge: text and symbol always carry the meaning, colour only
/// reinforces it.
struct BadgeSpec {
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
