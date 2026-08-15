import Foundation
import OttoDomain
import OttoServices

// Export and import (Wave 8), split out of AppModel.swift when F8's prepared-
// export state pushed that file past SwiftLint's 400-line `file_length`. The
// seam is the obvious one and the one the MARK already drew: AppModel.swift
// owns the model graph and the §5.4 flows, this owns the CloudKit escape hatch
// and the state that decides whether a built file may still be offered.
//
// `prepared`, `preparing`, `exportFailures` and `exportGeneration` stay on the
// main type because stored properties cannot live in an extension; everything
// that reads or writes them is here.
extension AppModel {

    // MARK: - Export and import (Wave 8)

    /// The export files this session has been ASKED for, by kind (F8).
    ///
    /// An export is a complete, unencrypted copy of the user's finances.
    /// Building one on a view's `.task` wrote both of them into the temporary
    /// directory every time the user so much as opened Settings - measured at
    /// `2d8913c` by rendering the real screen: two `completeSnapshot()` calls
    /// and two files on disk from an appearance alone, with nothing asked for
    /// and nothing shared.
    ///
    /// Kept on the model rather than in the view's `@State` for the second half
    /// of the same defect, R0-10(b): the file describes the database at the
    /// instant it was built, so whatever replaces the database has to be able
    /// to withdraw it. A view's `@State` is reachable from nothing that knows
    /// an import happened, which is exactly why the share sheet went on
    /// offering the pre-import copy.

    /// What one export row is showing.
    ///
    /// Owned here rather than in the view's `@State` for the same reason the
    /// URLs are: a `private struct` view's state is unreachable from every test
    /// and from every path that has to withdraw it. Keeping the whole state
    /// machine on the model leaves the view one call wide.
    public enum ExportAvailability: Equatable, Sendable {
        case notPrepared
        case preparing
        case ready(URL)
        case failed(String)
    }

    public func exportAvailability(_ kind: ExportKind) -> ExportAvailability {
        if let url = prepared[kind] { return .ready(url) }
        if preparing.contains(kind) { return .preparing }
        if let message = exportFailures[kind] { return .failed(message) }
        return .notPrepared
    }

    /// The file ready to share for `kind`, or nil when none has been asked for
    /// since the last change to the database.
    public func preparedExport(_ kind: ExportKind) -> URL? { prepared[kind] }

    /// The user asked for an export. Starts the build and returns its `Task`, so
    /// the view's button action is one call with no logic in it and a test can
    /// await exactly what the tap started.
    @discardableResult
    public func requestExport(_ kind: ExportKind) -> Task<Void, Never> {
        Task { [weak self] in
            _ = try? await self?.prepareExport(kind)
        }
    }

    /// Builds one export because the user asked for it, and remembers that they
    /// did. The only path in this module that writes an export file.
    ///
    /// Per KIND, not global: preparing the JSON backup must not clear the CSV
    /// row's in-flight state or its failure, which a single-valued flag did.
    @discardableResult
    public func prepareExport(_ kind: ExportKind) async throws -> URL {
        preparing.insert(kind)
        exportFailures[kind] = nil
        let generation = exportGeneration
        do {
            let url = switch kind {
            case .json:
                try await exports.exportJSONFile(exportedAt: dates.now(), today: dates.today())
            case .chargesCSV:
                try await exports.exportChargesCSVFile(today: dates.today())
            }
            preparing.remove(kind)
            // A withdrawal that landed while this was suspended WINS. The file
            // was built from a snapshot that is no longer the database, so
            // installing it here would re-offer exactly the staleness the
            // withdrawal exists to remove. The caller still gets the URL it
            // asked for; what it does not get is a place in the share sheet.
            guard generation == exportGeneration else { return url }
            prepared[kind] = url
            return url
        } catch {
            preparing.remove(kind)
            // Same generation check as the success branch: a failure recorded
            // for a database that has since changed is as stale as a file built
            // from it, and leaving it on the row shows the user an error about
            // data they have already replaced (`reviews-4/REVIEW-4.md`).
            if generation == exportGeneration {
                exportFailures[kind] = error.localizedDescription
            }
            throw error
        }
    }

    /// Stops offering every prepared export (R0-10(b)).
    ///
    /// Called wherever this model knows the database changed. The file on disk
    /// is left alone - it is in the temporary directory and the system reclaims
    /// it - because deleting a file the share sheet may already be reading is a
    /// worse failure than leaving one behind. What changes is that Otto stops
    /// handing it out.
    ///
    /// **It is not called from everywhere data changes**, and the app no longer
    /// claims it is. `NotificationActionHandler` writes state through
    /// `model.flows` without passing through this model at all, and a scheduling
    /// pass materializes ledger rows the CSV prints; neither withdraws.
    /// `PROD-READINESS-4.md` N4-4 carries both with the reviewer's evidence.
    public func withdrawPreparedExports() {
        prepared.removeAll()
        exportFailures.removeAll()
        exportGeneration += 1
    }

    /// What an import of `url` would bring, and whether the merge-or-replace
    /// question even arises. Touches nothing.
    public func importPreview(from url: URL) async throws -> ImportPreview {
        try await exports.importPreview(from: url)
    }

    /// Runs the import, then treats it as the large mutation it is: reschedule
    /// (which also materializes the imported subscriptions' ledgers) and
    /// refresh every published list.
    public func importData(from url: URL, strategy: ImportStrategy) async throws -> ImportSummary {
        let summary = try await exports.performImport(from: url, strategy: strategy, now: dates.now())
        await flowFinished()
        await paymentMethodsStore.refresh()
        return summary
    }
}
