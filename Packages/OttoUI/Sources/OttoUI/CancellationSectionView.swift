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

    @ViewBuilder
    var body: some View {
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
                evidenceRow(record: record)
                verificationPrompt(record: record)
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
            if detail.cancellation == nil && detail.subscription.status != .archived {
                Button(String(localized: "Mark as cancelling…")) {
                    isCancelling = true
                }
            }
        } header: {
            Text(String(localized: "Cancelling"))
        } footer: {
            if detail.cancellation == nil && detail.subscription.status != .archived {
                Text(String(localized: """
                Otto never cancels anything for you. It opens the page, records \
                what you did, and later checks that the money actually stopped.
                """))
            }
        }
        disputeSection
    }

    /// The captured evidence, editable in place - the confirmation number usually
    /// arrives only after the vendor page has been fought through.
    @ViewBuilder
    private func evidenceRow(record: CancellationRecord) -> some View {
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

    /// The verification question (spec §5.4, §7.1 screen 6), shown once the check
    /// date has arrived - and kept on screen for an escalated record, which is
    /// exactly a check that went unanswered three times.
    @ViewBuilder
    private func verificationPrompt(record: CancellationRecord) -> some View {
        let today = model.subscriptionsStore.today
        let checkDue = record.verificationState == .pending
            && record.nextChargeDateIfNotCancelled <= today
        if checkDue || record.verificationState == .needsManualReview {
            let name = detail.subscription.name
            let due = record.nextChargeDateIfNotCancelled.displayText()
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
}
