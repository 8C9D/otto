import SwiftUI
import OttoDomain
import OttoStores

/// Detail's cancellation block (spec §7.1 screens 5 and 6): the watching record,
/// the evidence, the verification question when its date arrives, and the
/// dispute summary when a charge got through. Its own view because it is a whole
/// flow, not a row.
struct CancellationSectionView: View {
    let detail: SubscriptionDetail
    @Binding var isCancelling: Bool
    /// The host screen's run-and-refresh wrapper, so failures surface in one place.
    let perform: (@escaping () async throws -> Void) -> Void
    @Environment(AppModel.self) private var model
    @State private var isEditingEvidence = false
    @State private var evidenceDraft = ""
    @State private var resumeDateDraft: CalendarDay?

    @ViewBuilder
    var body: some View {
        Section {
            if let record = detail.cancellation {
                LabeledContent(
                    String(localized: "Marked cancelled"),
                    value: record.markedCancelledAt.formatted(date: .abbreviated, time: .omitted)
                )
                if let checkDate = record.nextChargeDateIfNotCancelled {
                    LabeledContent(
                        String(localized: "Watching for a charge on"),
                        value: checkDate.displayText()
                    )
                }
                LabeledContent(String(localized: "Verification")) {
                    verificationBadge(record.verificationState)
                }
                evidenceRow(record: record)
                resumeDatePrompt(record: record)
                verificationPrompt(record: record)
                abandonRow
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
            if detail.cancellation == nil && !isArchived {
                Button(String(localized: "Mark as cancelling…")) {
                    isCancelling = true
                }
            }
        } header: {
            Text(String(localized: "Cancelling"))
        } footer: {
            if detail.cancellation == nil && !isArchived {
                Text(String(localized: """
                Otto never cancels anything for you. It opens the page, records \
                what you did, and later checks that the money actually stopped.
                """))
            }
        }
        disputeSection
    }

    /// Effective, not stored (spec §5.2a, v1.7) - equivalent today, since
    /// nothing derives into or out of `.archived`.
    private var isArchived: Bool {
        detail.subscription.effectiveStatus(asOf: model.subscriptionsStore.today) == .archived
    }

    /// The un-cancel (spec §5.4, §5.3a): an accidental "I'm cancelling" tap
    /// used to be irreversible in-app. The episode closes as `.abandoned` and
    /// stays in history - "I thought I'd cancelled this and hadn't" is exactly
    /// the data Otto is for - and the subscription goes back to the state the
    /// cancellation interrupted.
    @ViewBuilder
    private var abandonRow: some View {
        if !isArchived {
            Button {
                perform {
                    try await model.abandonCancellation(subscriptionID: detail.subscription.id)
                }
            } label: {
                Label(
                    String(localized: "I'm not cancelling after all"),
                    systemImage: "arrow.uturn.backward"
                )
            }
        }
    }

    /// The captured evidence, editable in place - the confirmation number usually
    /// arrives only after the vendor page has been fought through.
    @ViewBuilder
    private func evidenceRow(record: CancellationEpisode) -> some View {
        Button {
            evidenceDraft = record.evidenceNote ?? ""
            isEditingEvidence = true
        } label: {
            if let note = record.evidenceNote {
                LabeledContent(String(localized: "Evidence"), value: note)
            } else {
                Label(
                    String(localized: "Add a confirmation number or note"),
                    systemImage: "square.and.pencil"
                )
            }
        }
        .alert(
            String(localized: "Cancellation evidence"),
            isPresented: $isEditingEvidence
        ) {
            TextField(
                String(localized: "Confirmation number, rep's name…"),
                text: $evidenceDraft
            )
            Button(String(localized: "Save")) {
                perform {
                    try await model.updateCancellationEvidence(
                        subscriptionID: detail.subscription.id, note: evidenceDraft
                    )
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: """
            Whatever a dispute would need later: confirmation number, \
            who you spoke to, a screenshot's whereabouts.
            """))
        }
    }

    /// The deferred check asking for its date (spec §5.4, v1.5): the
    /// subscription was cancelled while paused indefinitely, no would-be charge
    /// date honestly exists, and Otto will not fabricate one. The user supplies
    /// the resume date the vendor gave; the watch starts from it.
    @ViewBuilder
    private func resumeDatePrompt(record: CancellationEpisode) -> some View {
        if record.verificationState == .awaitingResumeDate {
            let name = detail.subscription.name
            Text(String(localized: """
            \(name) was paused with no resume date when you cancelled, so there \
            is no date to watch yet. When was billing due to resume?
            """))
                .font(.callout)
            DatePicker(
                String(localized: "Billing was due to resume"),
                selection: Binding(
                    get: { resumeDateDraft ?? model.subscriptionsStore.today },
                    set: { resumeDateDraft = $0 }
                ).asDate()
            )
            .datePickerStyle(.compact)
            Button(String(localized: "Start watching from this date")) {
                let chosen = resumeDateDraft ?? model.subscriptionsStore.today
                perform {
                    try await model.supplyPausedResumeDate(
                        subscriptionID: detail.subscription.id, resumeDate: chosen
                    )
                }
            }
        }
    }

    /// The verification question (spec §5.4, §7.1 screen 6), shown once the check
    /// date has arrived - and kept on screen for an escalated record, which is
    /// exactly a check that went unanswered three times.
    @ViewBuilder
    private func verificationPrompt(record: CancellationEpisode) -> some View {
        let today = model.subscriptionsStore.today
        if let checkDate = record.nextChargeDateIfNotCancelled,
           (record.verificationState == .pending && checkDate <= today)
            || record.verificationState == .needsManualReview {
            let name = detail.subscription.name
            let due = checkDate.displayText()
            Text(String(localized: "A \(name) charge was due \(due). Check your statement - did it stop?"))
                .font(.callout)
            Button(String(localized: "Yes - the charges stopped")) {
                perform {
                    _ = try await model.answerVerification(
                        subscriptionID: detail.subscription.id, chargesStopped: true
                    )
                }
            }
            Button(String(localized: "No - it charged again"), role: .destructive) {
                perform {
                    _ = try await model.answerVerification(
                        subscriptionID: detail.subscription.id, chargesStopped: false
                    )
                }
            }
        }
    }

    /// The dispute summary (spec §5.4): every fact a bank needs, readable aloud,
    /// shareable as text. Shown as long as the record says a charge arrived.
    @ViewBuilder
    private var disputeSection: some View {
        if let record = detail.cancellation,
           let summary = disputeSummary(for: record, subscription: detail.subscription) {
            Section {
                Text(summary.spokenText())
                    .font(.callout)
                    .textSelection(.enabled)
                ShareLink(item: summary.spokenText()) {
                    Label(String(localized: "Share for a dispute"), systemImage: "square.and.arrow.up")
                }
                Button(String(localized: "Resolved - the charges have stopped")) {
                    perform {
                        _ = try await model.answerVerification(
                            subscriptionID: detail.subscription.id, chargesStopped: true
                        )
                    }
                }
            } header: {
                Text(String(localized: "Dispute this charge"))
            } footer: {
                Text(String(localized: "Read this to your bank or card issuer, or screenshot it."))
            }
        }
    }

    private func verificationBadge(_ state: CancellationEpisode.VerificationState) -> some View {
        let badge: BadgeSpec = switch state {
        case .pending:
            BadgeSpec(text: String(localized: "Waiting"), symbolName: "clock", color: .orange)
        case .verifiedStopped:
            BadgeSpec(text: String(localized: "Charges stopped"), symbolName: "checkmark.circle", color: .green)
        case .stillCharging:
            BadgeSpec(text: String(localized: "Still charging"), symbolName: "exclamationmark.triangle", color: .red)
        case .needsManualReview:
            BadgeSpec(text: String(localized: "Needs review"), symbolName: "exclamationmark.triangle", color: .red)
        case .awaitingResumeDate:
            BadgeSpec(text: String(localized: "Needs a resume date"), symbolName: "calendar.badge.exclamationmark", color: .orange)
        }
        return badge.label
    }
}
