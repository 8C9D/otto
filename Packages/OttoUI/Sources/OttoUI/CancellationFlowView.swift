import SwiftUI
import OttoDomain
import OttoStores

/// The guided cancellation flow (spec §5.4, §7.1 screen 5): mark it cancelling,
/// capture the evidence, open the vendor page, and let Otto schedule the check
/// that makes the cancellation real. Otto never cancels anything itself - the
/// differentiating promise is that it keeps watching after you do.
struct CancellationFlowView: View {
    let subscription: Subscription
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationNumber = ""
    @State private var notes = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: """
                    Cancel with \(subscription.name) yourself - Otto records what \
                    you did and checks later that the money actually stopped.
                    """))
                        .font(.callout)
                    if let url = subscription.cancellationURL {
                        Link(destination: url) {
                            Label(String(localized: "Open cancellation page"), systemImage: "safari")
                        }
                    }
                    if let howTo = subscription.cancellationNotes {
                        Text(howTo)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField(String(localized: "Confirmation number"), text: $confirmationNumber)
                    TextField(
                        String(localized: "Notes - rep's name, screenshot, anything"),
                        text: $notes,
                        axis: .vertical
                    )
                } header: {
                    Text(String(localized: "Evidence"))
                } footer: {
                    Text(String(localized: """
                    Add it now or after you've cancelled - this is what a dispute \
                    will need if the charges don't stop.
                    """))
                }

                Section {
                    Button(String(localized: "Mark as cancelling")) {
                        Task { await markCancelling() }
                    }
                } footer: {
                    if let checkDate = verificationCheckDate(
                        for: subscription, cancelledOn: model.subscriptionsStore.today
                    ) {
                        Text(String(localized: """
                        Otto will check with you on \(checkDate.displayText()) - the \
                        first day a charge would land if the cancellation didn't take.
                        """))
                    } else {
                        // The indefinitely paused cancellation (spec §5.4): no
                        // honest check date exists, and Otto says so instead of
                        // inventing one.
                        Text(String(localized: """
                        This subscription is paused with no resume date, so there is \
                        no date to watch yet. Otto will ask for the resume date after \
                        you mark it cancelled.
                        """))
                    }
                }
            }
            .navigationTitle(String(localized: "Cancelling \(subscription.name)"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Not yet")) { dismiss() }
                }
            }
            .alert(
                String(localized: "Couldn't mark it"),
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

    /// The evidence as one note: confirmation number first, free text after.
    private var evidenceNote: String? {
        let confirmation = confirmationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !confirmation.isEmpty {
            parts.append(String(localized: "Confirmation: \(confirmation)"))
        }
        if !extra.isEmpty {
            parts.append(extra)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func markCancelling() async {
        do {
            try await model.startCancellation(
                subscriptionID: subscription.id, evidenceNote: evidenceNote
            )
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
