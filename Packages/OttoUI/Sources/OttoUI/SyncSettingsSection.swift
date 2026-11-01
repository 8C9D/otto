import SwiftUI
import OttoRepositories
import OttoServices
import OttoStores

/// iCloud sync in Settings (spec §8, Wave 6B): turning it on, seeing whether it
/// is working, and the three actions for the worst day - stop, resume, and
/// deleting the cloud copy. Every switch acts at the next launch, and every
/// state below says so, because nothing else on screen changes when one flips.
struct SyncSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingEnable = false
    @State private var isConfirmingStop = false
    @State private var isConfirmingDelete = false
    @State private var isWorking = false
    @State private var backupName: String?
    @State private var failure: String?

    var body: some View {
        Section {
            LabeledContent(String(localized: "iCloud sync"), value: statusText)
            actions
        } footer: {
            Text(footerText)
        }
        .confirmationDialog(
            String(localized: "Turn on iCloud sync?"), isPresented: $isConfirmingEnable, titleVisibility: .visible
        ) {
            Button(String(localized: "Back Up and Turn On")) { run { sync in
                let url = try await sync.turnOn()
                backupName = url.lastPathComponent
            } }
        } message: {
            Text(String(localized: """
            Otto saves a backup to the Files app first, then syncs through your iCloud \
            account from the next time you open it. If you sign out of iCloud or turn \
            iCloud off for Otto, iOS removes synced subscriptions from this device \
            until you sign back in.
            """))
        }
        .confirmationDialog(
            String(localized: "Stop syncing on this device?"), isPresented: $isConfirmingStop, titleVisibility: .visible
        ) {
            Button(String(localized: "Stop Syncing")) { run { await $0.stopSyncing() } }
        } message: {
            Text(String(localized: """
            Takes effect the next time you open Otto. Nothing is deleted, here or in \
            iCloud, and your other devices keep syncing.
            """))
        }
        .confirmationDialog(
            String(localized: "Delete Otto's copy from iCloud?"), isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button(String(localized: "Delete from iCloud"), role: .destructive) {
                run { try await $0.deleteCloudCopy() }
            }
        } message: {
            Text(String(localized: """
            This can't be undone. This device keeps its data, and so do your other \
            devices - but one that is still syncing will put its copy back, so stop \
            syncing there first.
            """))
        }
        .alert(
            String(localized: "Backup saved"),
            isPresented: Binding(get: { backupName != nil }, set: { if !$0 { backupName = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: """
            \(backupName ?? "") is in the Files app, under On My iPhone › Otto. \
            Close and reopen Otto to start syncing.
            """))
        }
        .alert(
            String(localized: "iCloud sync"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .task { await model.sync?.refreshAccount() }
    }

    private var presentation: SyncPresentation {
        model.sync?.presentation ?? .unavailable
    }

    @ViewBuilder
    private var actions: some View {
        switch presentation {
        case .unavailable:
            EmptyView()
        case .off:
            actionButton(String(localized: "Turn On iCloud Sync…"), systemImage: "icloud") {
                isConfirmingEnable = true
            }
        case .syncing, .failedToOpen, .startsNextLaunch:
            actionButton(String(localized: "Stop Syncing…"), systemImage: "stop.circle") {
                isConfirmingStop = true
            }
        case .stopsNextLaunch:
            actionButton(String(localized: "Keep Syncing"), systemImage: "arrow.uturn.backward") {
                run { await $0.resumeSyncing() }
            }
        case .stopped:
            actionButton(String(localized: "Resume Syncing"), systemImage: "icloud") {
                run { await $0.resumeSyncing() }
            }
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label(String(localized: "Delete Copy from iCloud…"), systemImage: "trash")
            }
            .disabled(isWorking)
        }
    }

    private func actionButton(
        _ title: String, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .disabled(isWorking)
    }

    private func run(_ work: @escaping (SyncStatusStore) async throws -> Void) {
        guard let sync = model.sync else { return }
        isWorking = true
        Task {
            do {
                try await work(sync)
            } catch {
                failure = error.localizedDescription
            }
            isWorking = false
        }
    }

    private var statusText: String {
        switch presentation {
        case .unavailable, .off: String(localized: "Off")
        case .startsNextLaunch: String(localized: "Starts next launch")
        case .stopsNextLaunch: String(localized: "Stops next launch")
        case .stopped: String(localized: "Stopped")
        case .failedToOpen: String(localized: "Couldn't start")
        case .syncing: onStatusText
        }
    }

    private var onStatusText: String {
        guard let sync = model.sync else { return String(localized: "On") }
        if sync.isAccountMissing { return String(localized: "Signed out") }
        switch sync.activity.lastFailure {
        case .accountUnavailable: return String(localized: "Signed out")
        case .networkUnavailable: return String(localized: "Waiting for a connection")
        case .quotaExceeded: return String(localized: "iCloud storage full")
        case .partial: return String(localized: "Changes not uploading")
        case .other: return String(localized: "Trouble syncing")
        case nil: break
        }
        if sync.activity.isImporting || sync.activity.isExporting {
            return String(localized: "Syncing…")
        }
        return sync.activity.lastSuccessAt == nil
            ? String(localized: "Waiting for iCloud")
            : String(localized: "Up to date")
    }

    private var footerText: String {
        switch presentation {
        case .unavailable:
            String(localized: """
            Sync and automatic backup arrive in a later update. Until then, the \
            JSON export above is your backup - a good habit after big changes.
            """)
        case .off:
            String(localized: """
            Keeps Otto's data in your own iCloud account, so it survives a lost phone \
            and reaches your other devices. Otto has no server and can't see it.
            """)
        case .startsNextLaunch:
            String(localized: "Close and reopen Otto to start syncing.")
        case .syncing:
            onFooterText
        case .stopsNextLaunch:
            String(localized: "Close and reopen Otto to stop syncing. Other devices keep syncing.")
        case .stopped:
            String(localized: """
            This device isn't syncing. Your iCloud copy is untouched, and changes made \
            here wait until you resume. Importing a backup is only possible in this state.
            """)
        case .failedToOpen:
            String(localized: """
            Otto opened your data on this device instead, and nothing was lost. Stop \
            syncing so Otto stops retrying, or reopen Otto to try again.
            """)
        }
    }

    private var onFooterText: String {
        if model.sync?.activity.lastFailure == .quotaExceeded {
            return String(localized: """
            Your iCloud storage is full, so changes made here aren't reaching iCloud \
            or your other devices. Nothing is lost on this device.
            """)
        }
        // "Usually", because that is all the framework's event lets Otto know.
        if model.sync?.activity.lastFailure == .partial {
            return String(localized: """
            Some changes made here aren't reaching iCloud or your other devices, \
            usually because your iCloud storage is full. They stay on this device.
            """)
        }
        return String(localized: """
        Changes reach your other devices through your iCloud account. To import a \
        backup, stop syncing first.
        """)
    }
}
