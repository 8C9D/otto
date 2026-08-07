import SwiftUI
import OttoDomain

/// A subscription status as symbol + text. Colour reinforces but never carries the
/// meaning alone (Wave 3 constraint) - the label and symbol always say it too.
struct StatusBadge: View {
    let status: SubscriptionStatus

    var body: some View {
        Label(text, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }

    private var text: String {
        switch status {
        case .trial: String(localized: "Trial")
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case .cancellationPending: String(localized: "Cancelling")
        case .cancelled: String(localized: "Cancelled")
        case .archived: String(localized: "Archived")
        }
    }

    private var symbolName: String {
        switch status {
        case .trial: "hourglass"
        case .active: "checkmark.circle"
        case .paused: "pause.circle"
        case .cancellationPending: "clock.arrow.circlepath"
        case .cancelled: "eye"
        case .archived: "archivebox"
        }
    }

    private var color: Color {
        switch status {
        case .trial: .orange
        case .active: .green
        case .paused: .gray
        case .cancellationPending, .cancelled: .blue
        case .archived: .gray
        }
    }
}
