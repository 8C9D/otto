import Foundation
import OttoDomain
import OttoRepositories

/// What an import needs the user to decide before it runs: whether anything is
/// already here (an empty database needs no merge-or-replace question), and
/// what the file would bring in. The counts are LIVE records only (Wave 10,
/// defect H): tombstones ride along for sync correctness but are not data the
/// user would recognize as "in the file".
public struct ImportPreview: Hashable, Sendable {
    public let databaseIsEmpty: Bool
    public let subscriptionCount: Int
    public let billingEventCount: Int
    public let paymentMethodCount: Int
}

/// What the document picker handed back (R0-10(a)).
///
/// The `.failure` half of `.fileImporter`'s result used to be dropped on the
/// floor - no log, no alert - so a genuine read error on the RECOVERY path was
/// indistinguishable from the user changing their mind. Both now have a name,
/// and only one of them is worth interrupting the user for.
public enum ImportPickerOutcome: Equatable {
    case selected(URL)
    case cancelled
    case failed(String)
}

/// Classifies a document-picker result and records it.
///
/// Lives here rather than in the view because the view's handler is inside a
/// `private struct` nothing can call, and an unreachable decision is an
/// unguarded one - the lesson round 2 relearned three times.
///
/// Whether SwiftUI reports a dismissed picker as `CocoaError.userCancelled` or
/// as no callback at all is a detail of the framework version, so both are
/// handled; only the real failure is surfaced to the user.
public func importPickerOutcome(of result: Result<URL, any Error>) -> ImportPickerOutcome {
    switch result {
    case .success(let url):
        return .selected(url)
    case .failure(let error) where (error as? CocoaError)?.code == .userCancelled:
        OttoLog.dataTransfer.notice("import picker cancelled")
        return .cancelled
    case .failure(let error):
        OttoLog.dataTransfer.error("""
            import picker FAILED \
            error=\(String(describing: type(of: error)), privacy: .public)
            """)
        return .failed(error.localizedDescription)
    }
}

/// Which export the user asked for (F8).
///
/// Named rather than left as two separate methods on the model, because the
/// thing that has to be tracked is *which* complete financial records this
/// session has been asked to build - and a registry keyed by a method name is
/// not a registry.
public enum ExportKind: String, Hashable, Sendable, CaseIterable {
    /// The full-fidelity backup: every subscription, charge and price change.
    case json
    /// The lossy, one-way charge-history CSV.
    case chargesCSV
}

/// Layer 4 for export/import (spec §3.4): every serialization decision lives in
/// the domain (`exportData`, `decodeExport`, `resolveImport`, `chargesCSV`);
/// this actor only moves bytes between the repository and files. Export files
/// land in the temporary directory under stable dated names, ready for the
/// share sheet.
///
/// **Nothing here decides WHEN to write.** F8 was not a defect in this actor -
/// it writes a file when it is told to, which is its job - but in the caller:
/// `ExportSection` carried `.task { await regenerate() }`, so arriving on
/// Settings built both records for a user who had asked for neither.
/// `AppModel.prepareExport(_:)` is the only caller now, and it exists so that
/// "the user asked" is a state a test can read.
public actor ExportService {

    private let transfer: any DataTransferRepository

    public init(transfer: any DataTransferRepository) {
        self.transfer = transfer
    }

    // MARK: - Export

    /// The full-fidelity JSON export (spec §3.5) written to a shareable file.
    /// `exportedAt`/`today` come from the caller - no clock is read here.
    public func exportJSONFile(exportedAt: Date, today: CalendarDay) async throws -> URL {
        let snapshot = try await transfer.completeSnapshot()
        let data = try exportData(from: snapshot, exportedAt: exportedAt)
        let url = try write(data, filename: "Otto-Export-\(today).json")
        // Counts and bytes, never the path: an export lands under a dated Otto
        // name but the same helper writes wherever it is told, and a path can
        // carry the user's name.
        OttoLog.dataTransfer.notice("""
            export kind=json subscriptions=\(snapshot.subscriptions.count, privacy: .public) \
            events=\(snapshot.billingEvents.count, privacy: .public) \
            bytes=\(data.count, privacy: .public)
            """)
        return url
    }

    /// The lossy, one-way charge-history CSV, for reading in a spreadsheet.
    public func exportChargesCSVFile(today: CalendarDay) async throws -> URL {
        let snapshot = try await transfer.completeSnapshot()
        let csv = chargesCSV(from: snapshot)
        let data = Data(csv.utf8)
        let url = try write(data, filename: "Otto-Charges-\(today).csv")
        OttoLog.dataTransfer.notice("""
            export kind=csv events=\(snapshot.billingEvents.count, privacy: .public) \
            bytes=\(data.count, privacy: .public)
            """)
        return url
    }

    // MARK: - Import

    /// Reads and fully validates the file, returning what the UI needs to ask
    /// the merge-or-replace question. Touches nothing.
    public func importPreview(from url: URL) async throws -> ImportPreview {
        do {
            let incoming = try importedSnapshot(from: readSecurityScoped(url))
            let current = try await transfer.completeSnapshot()
            let preview = ImportPreview(
                databaseIsEmpty: current.isEmpty,
                subscriptionCount: incoming.subscriptions.count { $0.deletedAt == nil },
                billingEventCount: incoming.billingEvents.count { $0.deletedAt == nil },
                paymentMethodCount: incoming.paymentMethods.count { $0.deletedAt == nil }
            )
            OttoLog.dataTransfer.notice("""
                import preview subscriptions=\(preview.subscriptionCount, privacy: .public) \
                events=\(preview.billingEventCount, privacy: .public) \
                databaseEmpty=\(preview.databaseIsEmpty, privacy: .public)
                """)
            return preview
        } catch {
            // A file that cannot be read is the recovery path failing at its
            // first step, and it used to reach only an alert the user dismisses.
            OttoLog.dataTransfer.error(
                "import preview FAILED error=\(String(describing: type(of: error)), privacy: .public)"
            )
            throw error
        }
    }

    /// Decode → resolve → atomic restore. Any failure before the restore leaves
    /// the store untouched by construction; the restore itself is a single
    /// transaction that rolls back wholesale. `now` stamps the tombstones a
    /// replace writes for records the file does not carry (no clock is read
    /// here).
    @discardableResult
    public func performImport(from url: URL, strategy: ImportStrategy, now: Date) async throws -> ImportSummary {
        let incoming = try importedSnapshot(from: readSecurityScoped(url))
        let current = try await transfer.completeSnapshot()
        let resolved = try resolveImport(current: current, incoming: incoming, strategy: strategy, at: now)
        // A replace reconstructs this device's ledger progress from the
        // imported ledger (spec §5.3, v2.1 - a nil watermark is the founding
        // hazard, so the old reset is gone); a merge leaves it untouched. The
        // store owns the whole sequence - dirty flag, restore, reconstruction -
        // so the v2.2 crash window between its two saves self-heals instead of
        // depending on this caller's ordering.
        //
        // An import into an EMPTY database reconstructs too, whatever the
        // strategy says. The policy is about whether this device has ledger
        // progress worth keeping, and an empty database has none - "keep" keeps
        // nothing. It matters because the empty database IS the recovery case:
        // the UI does not ask merge-or-replace when there is nothing to merge
        // with (SettingsView), so restoring after a reinstall arrives here as a
        // merge, and .keep left every watermark nil. A nil watermark makes
        // materializeEvents start from TODAY and skip the window back to the
        // last real charge (OttoStore+BillingEvents), so the restored ledger
        // silently loses the rows between the file's last charge and today -
        // on the one path whose entire purpose is getting them back.
        // `hasNoLiveSubscriptions`, not `isEmpty`. The principle above is about
        // ledger progress, and a watermark is per-subscription, so a database
        // whose subscriptions are all tombstoned has none - but it is not
        // `isEmpty`, because `completeSnapshot()` carries tombstones by design.
        // So the UI does ask merge-or-replace there, and answering Merge
        // reproduced F6 exactly: nil watermark, and the rows between the file's
        // last charge and today silently never created. The prompt is still
        // right to appear - a replace and a merge really do differ for the
        // tombstones - it is only the WATERMARK decision that must follow the
        // principle rather than the record count.
        let reconstruct = strategy == .replace || current.hasNoLiveSubscriptions
        // BEFORE the restore, so an import that dies mid-transaction still
        // leaves a record of what was attempted. The pair of lines is the
        // point: a begin with no end is exactly the state Gate 3 had to
        // reconstruct by copying the container off the device.
        OttoLog.dataTransfer.notice("""
            import begin strategy=\(strategy.rawValue, privacy: .public) \
            watermarks=\(reconstruct ? "reconstruct" : "keep", privacy: .public) \
            incoming=\(incoming.subscriptions.count, privacy: .public)
            """)
        do {
            try await transfer.restore(
                resolved.snapshot, at: now,
                watermarks: reconstruct ? .reconstruct : .keep
            )
        } catch {
            OttoLog.dataTransfer.error("""
                import FAILED - nothing was applied \
                error=\(String(describing: type(of: error)), privacy: .public)
                """)
            throw error
        }
        let summary = resolved.summary
        OttoLog.dataTransfer.notice("""
            import end subscriptions=\(summary.subscriptions.added, privacy: .public)\
            +\(summary.subscriptions.updated, privacy: .public) \
            events=\(summary.billingEvents.added, privacy: .public)\
            +\(summary.billingEvents.updated, privacy: .public) \
            removed=\(summary.subscriptions.removed, privacy: .public) \
            stampOrderRepairs=\(summary.timestampOrderRepairs, privacy: .public) \
            futureStampClamps=\(summary.futureStampClamps, privacy: .public)
            """)
        return summary
    }

    // MARK: - Files

    private func write(_ data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Document-picker URLs arrive security-scoped; ours do not. Asking for
    /// access and being refused is fine as long as the read itself succeeds.
    private func readSecurityScoped(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}
