import SwiftUI
import UniformTypeIdentifiers
import OttoDomain
import OttoServices
import OttoStores
#if canImport(UIKit)
import UIKit
#endif

/// Settings (spec §7.1 item 9, Wave 8): the reminder defaults, the notification
/// time, the notification permission state, export/import - the CloudKit
/// escape hatch lives HERE, as a first-class feature - and the iCloud sync
/// placeholder Wave 6 fills in.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                ReminderDefaultsSection()
                NotificationPermissionSection()
                ExportSection()
                ImportSection()
                SyncPlaceholderSection()
            }
            .navigationTitle(String(localized: "Settings"))
        }
    }
}

// MARK: - Reminder defaults

private struct ReminderDefaultsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            Stepper(value: $settings.renewalLeadDays, in: 0 ... 30) {
                LabeledContent(
                    String(localized: "Renewal reminders"),
                    value: daysBeforeText(settings.renewalLeadDays)
                )
            }
            Stepper(value: $settings.trialLeadDays, in: 0 ... 30) {
                LabeledContent(
                    String(localized: "Trial reminders"),
                    value: daysBeforeText(settings.trialLeadDays)
                )
            }
            Stepper(value: $settings.trialBufferDays, in: 0 ... 14) {
                LabeledContent(
                    String(localized: "Trial cancel-by buffer"),
                    value: String(localized: "\(settings.trialBufferDays) days")
                )
            }
            DatePicker(
                String(localized: "Notification time"),
                selection: notificationTime,
                displayedComponents: .hourAndMinute
            )
        } header: {
            Text(String(localized: "Reminders"))
        } footer: {
            Text(String(localized: """
            The reminder defaults apply to subscriptions you add from now on - \
            each subscription keeps its own setting, editable on its screen. \
            The notification time applies to every reminder right away.
            """))
        }
    }

    private func daysBeforeText(_ days: Int) -> String {
        days == 0
            ? String(localized: "On the day")
            : String(localized: "\(days) days before")
    }

    /// The stored hour and minute as the `Date` a wheel picker needs. Both
    /// directions live on the store, where a test can reach them - see
    /// `SettingsStore.notificationTimeOfDay`.
    private var notificationTime: Binding<Date> {
        @Bindable var settings = model.settings
        return Binding<Date>(
            get: { settings.notificationTimeOfDay },
            set: { picked in settings.setNotificationTime(from: picked) }
        )
    }
}

// MARK: - Notification permission

private struct NotificationPermissionSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let notifications = model.notifications {
            Section(String(localized: "Notifications")) {
                switch notifications.permission {
                case .authorized:
                    Label(String(localized: "Notifications are on"), systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                case .provisional:
                    Label(
                        String(localized: "Quiet delivery - reminders go to Notification Center only"),
                        systemImage: "moon"
                    )
                case .notDetermined:
                    Button(String(localized: "Turn on reminders…")) {
                        Task { await notifications.requestPermission() }
                    }
                case .denied:
                    Label(String(localized: "Notifications are off"), systemImage: "bell.slash")
                        .foregroundStyle(.red)
                    Text(String(localized: """
                    Otto's whole job is reminding you before money moves. With \
                    notifications off it can only be useful while open.
                    """))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    settingsAppButton
                }
            }
            .task { await notifications.refreshPermission() }
        }
    }

    @ViewBuilder
    private var settingsAppButton: some View {
        #if canImport(UIKit)
        Button(String(localized: "Open Settings to allow them")) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
        #endif
    }
}

// MARK: - Export

private struct ExportSection: View {
    @Environment(AppModel.self) private var model

    /// F8: this section had `.task { await regenerate() }`, so ARRIVING here
    /// wrote the complete unencrypted JSON backup and the charge CSV into the
    /// temporary directory - for a user who had asked for neither, and every
    /// single time. Measured at `2d8913c` by rendering this screen in a window:
    /// two `completeSnapshot()` calls and two files on disk from the appearance
    /// alone.
    ///
    /// R0-10(b) was the same state a moment later: the two URLs lived in this
    /// view's `@State`, so the `ShareLink` beside them went on handing out the
    /// PRE-import file after an import replaced the database - measured on the
    /// same run, 0 subscriptions in the offered file after restoring 1.
    ///
    /// Both are fixed in one place by moving "which exports were asked for"
    /// onto the model, where the import path can withdraw them and a test can
    /// read them. Nothing here is written until a tap.
    var body: some View {
        Section {
            exportRow(
                .json,
                title: String(localized: "Export everything (JSON)"),
                symbol: "square.and.arrow.up"
            )
            exportRow(
                .chargesCSV,
                title: String(localized: "Export charge history (CSV)"),
                symbol: "tablecells"
            )
        } header: {
            Text(String(localized: "Back up"))
        } footer: {
            Text(String(localized: """
            The JSON file is the complete backup - every subscription, charge, \
            and price change, importable on this or another device. The CSV is \
            for reading in a spreadsheet; it can't be imported back.

            Otto builds a file only when you ask for it, so a complete copy of \
            your finances isn't left lying around. Editing a subscription or \
            importing a backup withdraws one you already built.
            """))
        }
    }

    /// Every branch reads the model, and the tap is one call with no logic in
    /// it. The state machine this used to hold in `@State` - which kind is
    /// preparing, which failed - is unreachable from any test in a `private
    /// struct`, and it could not represent two exports at once.
    @ViewBuilder
    private func exportRow(_ kind: ExportKind, title: String, symbol: String) -> some View {
        switch model.exportAvailability(kind) {
        case .ready(let url):
            ShareLink(item: url) {
                Label(title, systemImage: symbol)
            }
        case .preparing:
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "\(title), preparing"))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            retryButton(kind, title: title, symbol: symbol)
        case .notPrepared:
            retryButton(kind, title: title, symbol: symbol)
        }
    }

    private func retryButton(_ kind: ExportKind, title: String, symbol: String) -> some View {
        Button {
            model.requestExport(kind)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

// MARK: - Import

private struct ImportSection: View {
    @Environment(AppModel.self) private var model
    @State private var isPicking = false
    @State private var pendingURL: URL?
    @State private var pendingPreview: ImportPreview?
    @State private var summaryText: String?
    @State private var failure: String?

    var body: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                Label(String(localized: "Import from a backup…"), systemImage: "square.and.arrow.down")
            }
        } footer: {
            Text(String(localized: """
            Reads an Otto JSON export. A file that can't be read fully is \
            refused whole - an import never half-applies.
            """))
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.json]) { result in
            // R0-10(a): the `.failure` half used to be dropped entirely - no
            // log, no alert - so a genuine read failure on the RECOVERY path
            // was indistinguishable from the user changing their mind. The
            // alert it raises is the one that was already here (:275-285).
            switch importPickerOutcome(of: result) {
            case .selected(let url):
                Task { await preview(url) }
            case .cancelled:
                break
            case .failed(let description):
                failure = description
            }
        }
        .confirmationDialog(
            String(localized: "You already have data here"),
            isPresented: Binding(
                get: { pendingPreview != nil },
                set: { if !$0 { pendingPreview = nil; pendingURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Merge - keep both, newer copy wins")) {
                runPendingImport(strategy: .merge)
            }
            Button(String(localized: "Replace everything with the file"), role: .destructive) {
                runPendingImport(strategy: .replace)
            }
        } message: {
            if let pendingPreview {
                Text(String(localized: """
                The file has \(pendingPreview.subscriptionCount) subscriptions and \
                \(pendingPreview.billingEventCount) charge records. Merging keeps \
                everything from both, taking the newer copy where a record exists \
                in both. Replacing deletes what's here first.
                """))
            }
        }
        .alert(
            String(localized: "Import complete"),
            isPresented: Binding(
                get: { summaryText != nil },
                set: { if !$0 { summaryText = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(summaryText ?? "")
        }
        .alert(
            String(localized: "Nothing was imported"),
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

    /// An empty database has no merge-or-replace question to ask; a non-empty
    /// one always gets it - importing must never silently pick (Wave 8).
    private func preview(_ url: URL) async {
        do {
            let preview = try await model.importPreview(from: url)
            if preview.databaseIsEmpty {
                await run(url: url, strategy: .merge)
            } else {
                pendingURL = url
                pendingPreview = preview
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func runPendingImport(strategy: ImportStrategy) {
        guard let url = pendingURL else { return }
        pendingURL = nil
        pendingPreview = nil
        Task { await run(url: url, strategy: strategy) }
    }

    private func run(url: URL, strategy: ImportStrategy) async {
        do {
            let summary = try await model.importData(from: url, strategy: strategy)
            summaryText = summaryDescription(summary)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func summaryDescription(_ summary: ImportSummary) -> String {
        [
            entityLine(String(localized: "Subscriptions"), summary.subscriptions),
            entityLine(String(localized: "Charges"), summary.billingEvents),
            entityLine(String(localized: "Payment methods"), summary.paymentMethods),
            entityLine(String(localized: "Price changes"), summary.priceChanges),
            entityLine(String(localized: "Cancellation records"), summary.cancellationEpisodes)
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func entityLine(_ name: String, _ counts: ImportCounts) -> String? {
        var parts: [String] = []
        if counts.added > 0 { parts.append(String(localized: "\(counts.added) added")) }
        if counts.updated > 0 { parts.append(String(localized: "\(counts.updated) updated")) }
        if counts.skippedOlder > 0 {
            parts.append(String(localized: "\(counts.skippedOlder) kept (yours was newer)"))
        }
        if counts.removed > 0 { parts.append(String(localized: "\(counts.removed) removed")) }
        guard !parts.isEmpty else { return nil }
        return "\(name): \(parts.joined(separator: ", "))"
    }
}

// MARK: - iCloud placeholder

private struct SyncPlaceholderSection: View {
    var body: some View {
        Section {
            LabeledContent(String(localized: "iCloud sync"), value: String(localized: "Off"))
        } footer: {
            Text(String(localized: """
            Sync and automatic backup arrive in a later update. Until then, the \
            JSON export above is your backup - a good habit after big changes.
            """))
        }
    }
}
