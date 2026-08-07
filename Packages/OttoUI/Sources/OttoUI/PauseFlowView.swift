import SwiftUI
import OttoDomain
import OttoStores

/// The pause flow (spec §5.1): the vendor suspended billing - a gym freeze, a
/// seasonal hold - and Otto records it. The resume date is optional and honest:
/// with one, the resume is derived and the resumed charges are watched ahead of
/// time; without one, Otto freezes its bookkeeping and waits to be told.
struct PauseFlowView: View {
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

/// Detail's pause block (spec §5.1): a paused subscription resumes here, an
/// active one pauses through the flow above. A pause whose end date has already
/// passed is effectively active by derivation (spec §5.2a, v1.6); the row
/// states that fact and offers to persist it - persistence is an optimisation,
/// never the mechanism.
struct PauseSectionView: View {
    let detail: SubscriptionDetail
    @Binding var isPausing: Bool
    /// The host screen's run-and-refresh wrapper, so failures surface in one place.
    let perform: (@escaping () async throws -> Void) -> Void
    @Environment(AppModel.self) private var model

    @ViewBuilder
    var body: some View {
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
}

/// Detail's usage block (spec §7.3): the fact zombie detection counts from.
/// Only shown while something is actually billing - recording use of a
/// cancelled subscription would feed a report that no longer includes it.
struct UsageSectionView: View {
    let detail: SubscriptionDetail
    /// The host screen's run-and-refresh wrapper, so failures surface in one place.
    let perform: (@escaping () async throws -> Void) -> Void
    @Environment(AppModel.self) private var model

    @ViewBuilder
    var body: some View {
        let subscription = detail.subscription
        if subscription.effectiveStatus(asOf: model.subscriptionsStore.today) == .active {
            Section(String(localized: "Usage")) {
                LabeledContent(
                    String(localized: "Last recorded use"),
                    value: subscription.lastUsedDate?.displayText()
                        ?? String(localized: "Never recorded")
                )
                Button(String(localized: "I used this today")) {
                    perform { try await model.recordUsage(subscriptionID: subscription.id) }
                }
            }
        }
    }
}
