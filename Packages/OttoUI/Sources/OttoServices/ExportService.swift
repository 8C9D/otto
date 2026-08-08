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

/// Layer 4 for export/import (spec §3.4): every serialization decision lives in
/// the domain (`exportData`, `decodeExport`, `resolveImport`, `chargesCSV`);
/// this actor only moves bytes between the repository and files. Export files
/// land in the temporary directory under stable dated names, ready for the
/// share sheet.
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
        return try write(data, filename: "Otto-Export-\(today).json")
    }

    /// The lossy, one-way charge-history CSV, for reading in a spreadsheet.
    public func exportChargesCSVFile(today: CalendarDay) async throws -> URL {
        let snapshot = try await transfer.completeSnapshot()
        let csv = chargesCSV(from: snapshot)
        return try write(Data(csv.utf8), filename: "Otto-Charges-\(today).csv")
    }

    // MARK: - Import

    /// Reads and fully validates the file, returning what the UI needs to ask
    /// the merge-or-replace question. Touches nothing.
    public func importPreview(from url: URL) async throws -> ImportPreview {
        let incoming = try importedSnapshot(from: readSecurityScoped(url))
        let current = try await transfer.completeSnapshot()
        return ImportPreview(
            databaseIsEmpty: current.isEmpty,
            subscriptionCount: incoming.subscriptions.count { $0.deletedAt == nil },
            billingEventCount: incoming.billingEvents.count { $0.deletedAt == nil },
            paymentMethodCount: incoming.paymentMethods.count { $0.deletedAt == nil }
        )
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
        try await transfer.restore(
            resolved.snapshot, at: now,
            watermarks: strategy == .replace ? .reconstruct : .keep
        )
        return resolved.summary
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
