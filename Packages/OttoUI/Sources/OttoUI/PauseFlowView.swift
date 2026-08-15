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
        // Derivation APIs only (spec §5.2a, v1.7): a derived-resumed pause is
        // effectively active but still needs its persist-the-derivation row, so
        // it is asked for by name rather than via the stored status.
        if subscription.isResumedPause(asOf: today) {
            Section(String(localized: "Pause")) {
                let ended = subscription.pauseEndsOn.map { $0.displayText() } ?? ""
                Text(String(localized: "This pause ended \(ended) - billing has resumed."))
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button(String(localized: "Got it - mark as active")) {
                    perform { try await model.resumeSubscription(subscriptionID: subscription.id) }
                }
            }
        } else if subscription.effectiveStatus(asOf: today) == .paused {
            Section(String(localized: "Pause")) {
                Group {
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
/// Shown while something is actually billing - recording use of a cancelled
/// subscription would feed a report that no longer includes it - and ALSO
/// whenever the stored `lastUsedDate` is detected-implausible, whatever the
/// status (round 5, item 4 / N4-16): the button below is this field's only
/// writer, so gating it on the active state left a pre-F1 corrupt day with no
/// in-app repair short of a status change the user did not want.
struct UsageSectionView: View {
    let detail: SubscriptionDetail
    /// The host screen's run-and-refresh wrapper, so failures surface in one place.
    let perform: (@escaping () async throws -> Void) -> Void
    @Environment(AppModel.self) private var model

    /// The visibility rule, extracted so a host test can pin the whole
    /// status-by-plausibility matrix without a rendering pass.
    static func isShown(for subscription: Subscription, asOf today: CalendarDay) -> Bool {
        subscription.effectiveStatus(asOf: today) == .active
            || needsLastUsedDateRepair(subscription, asOf: today)
    }

    /// N4-16: a detected-implausible `lastUsedDate` gets the repair offered on
    /// ANY status. `nil` is not corruption - the check-in counts from the
    /// anchor instead - and a plausible day off the active state stays hidden,
    /// which is §7.3's rule unchanged.
    static func needsLastUsedDateRepair(
        _ subscription: Subscription, asOf today: CalendarDay
    ) -> Bool {
        guard let lastUsed = subscription.lastUsedDate else { return false }
        return !lastUsed.isPlausibleStoredDay(asOf: today)
    }

    @ViewBuilder
    var body: some View {
        let subscription = detail.subscription
        if Self.isShown(for: subscription, asOf: model.subscriptionsStore.today) {
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
