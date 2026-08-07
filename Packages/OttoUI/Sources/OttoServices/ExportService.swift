import Foundation
import OttoDomain
import OttoRepositories

/// What an import needs the user to decide before it runs: whether anything is
/// already here (an empty database needs no merge-or-replace question), and
/// what the file would bring in.
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
            subscriptionCount: incoming.subscriptions.count,
            billingEventCount: incoming.billingEvents.count,
            paymentMethodCount: incoming.paymentMethods.count
        )
    }

    /// Decode → resolve → atomic restore. Any failure before the restore leaves
    /// the store untouched by construction; the restore itself is a single
    /// transaction that rolls back wholesale.
    @discardableResult
    public func performImport(from url: URL, strategy: ImportStrategy) async throws -> ImportSummary {
        let incoming = try importedSnapshot(from: readSecurityScoped(url))
        let current = try await transfer.completeSnapshot()
        let resolved = try resolveImport(current: current, incoming: incoming, strategy: strategy)
        try await transfer.restore(resolved.snapshot)
        // A replace resets this device's ledger progress; a merge leaves it
        // untouched (spec §5.3, Wave 6B-Prep - the watermark lives only in the
        // device store now, so the reset is its own call, ordered after the
        // restore so a failed restore leaves device state exactly as it was).
        if strategy == .replace {
            try await transfer.resetMaterializationWatermarks()
        }
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
