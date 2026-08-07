import Foundation

/// Why an export file could not be read or written. Every case renders a
/// message a person can act on - an import that fails must say what it refused
/// and why, because the refusal happens exactly when the user is trying to
/// recover their data.
public enum ExportFormatError: Error, Hashable, LocalizedError {
    /// The file declares a format newer than this app reads. Refused OUTRIGHT:
    /// partially applying a future format is a silent data hole (Wave 8).
    case unsupportedFormatVersion(found: Int, supported: Int)
    /// The bytes are not an Otto export at all, or the JSON is damaged.
    case unreadable(details: String)
    /// A field carries a value format v1 does not define.
    case invalidValue(entity: String, field: String, value: String)
    /// A child row names a subscription that exists neither in the file nor in
    /// the database it is being imported into.
    case danglingReference(entity: String, subscriptionID: UUID)
    /// Two records claim the same subscription's single cancellation slot
    /// inside one file - the storage model holds exactly one.
    case duplicateCancellation(subscriptionID: UUID)

    // Plain strings, not String(localized:) - layer 1 stays framework-free and
    // the messages carry values localization tables cannot know.
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormatVersion(let found, let supported):
            return """
            This file uses Otto export format \(found), but this version of Otto \
            reads up to format \(supported). Update Otto, then import it again. \
            Nothing was changed.
            """
        case .unreadable(let details):
            return """
            This doesn't look like a readable Otto export file (\(details)). \
            Nothing was changed.
            """
        case .invalidValue(let entity, let field, let value):
            return """
            The export file is damaged: \(entity) has an impossible \(field) \
            ("\(value)"). Nothing was changed.
            """
        case .danglingReference(let entity, let subscriptionID):
            return """
            The export file is damaged: \(entity) belongs to a subscription \
            (\(subscriptionID.uuidString)) that the file does not contain. \
            Nothing was changed.
            """
        case .duplicateCancellation(let subscriptionID):
            return """
            The export file is damaged: it contains two cancellation records for \
            one subscription (\(subscriptionID.uuidString)). Nothing was changed.
            """
        }
    }
}

/// Encodes a snapshot as format v1 bytes: pretty-printed and key-sorted, so the
/// file is inspectable by eye and identical databases produce identical bytes.
public func exportData(from snapshot: OttoDataSnapshot, exportedAt: Date) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(OttoExport(snapshot: snapshot, exportedAt: exportedAt))
}

/// Decodes export bytes, version-checked FIRST: a file from a future Otto fails
/// with a clear message before anything else is looked at, and damaged JSON is
/// reported as unreadable rather than crashing or half-parsing.
public func decodeExport(_ data: Data) throws -> OttoExport {
    struct VersionProbe: Decodable { let formatVersion: Int }

    let decoder = JSONDecoder()
    let probe: VersionProbe
    do {
        probe = try decoder.decode(VersionProbe.self, from: data)
    } catch {
        throw ExportFormatError.unreadable(details: "no formatVersion field")
    }
    guard probe.formatVersion >= 1 else {
        throw ExportFormatError.unreadable(details: "formatVersion \(probe.formatVersion)")
    }
    guard probe.formatVersion <= OttoExport.currentFormatVersion else {
        throw ExportFormatError.unsupportedFormatVersion(
            found: probe.formatVersion, supported: OttoExport.currentFormatVersion
        )
    }
    do {
        return try decoder.decode(OttoExport.self, from: data)
    } catch let error as DecodingError {
        throw ExportFormatError.unreadable(details: describe(error))
    }
}

/// The snapshot an export file describes - decode, then domain validation.
public func importedSnapshot(from data: Data) throws -> OttoDataSnapshot {
    try decodeExport(data).snapshot()
}

private func describe(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context):
        "missing \(path(context))\(key.stringValue)"
    case .typeMismatch(_, let context), .dataCorrupted(let context):
        "damaged value at \(path(context))"
    case .valueNotFound(_, let context):
        "missing value at \(path(context))"
    @unknown default:
        "undecodable JSON"
    }
}

private func path(_ context: DecodingError.Context) -> String {
    context.codingPath.map { key in
        key.intValue.map { "[\($0)]." } ?? "\(key.stringValue)."
    }.joined()
}
