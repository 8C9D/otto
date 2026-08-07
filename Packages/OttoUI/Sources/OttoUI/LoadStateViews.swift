import SwiftUI
import OttoStores

/// The standard rendering of a failed load: what happened, and a retry. Kept as
/// one view so every screen fails the same way.
struct LoadFailedView: View {
    let error: any Error
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "Couldn't load"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button(String(localized: "Try Again")) {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
