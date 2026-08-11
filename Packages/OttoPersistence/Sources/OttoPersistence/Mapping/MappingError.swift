import Foundation

/// A persistence record could not produce a valid domain value.
///
/// This is a real runtime possibility, not a can't-happen: once CloudKit sync is on
/// (Wave 6), records arrive field by field, and a partially synced record is
/// indistinguishable from a corrupt one. Policy, applied consistently across the
/// store: the mapping layer always THROWS one of these; repository reads catch it
/// per record and SKIP the record with an error log, because a half-synced record
/// is - in domain terms - not there yet, and one bad row must not take down a whole
/// list read. Writes never map from records, so a write failure always surfaces to
/// the caller.
enum MappingError: Error, CustomStringConvertible {
    /// A field the domain requires was nil.
    case missingField(entity: String, field: String)
    /// A field held a value the domain rejects, e.g. an impossible yyyymmdd date
    /// or an unknown enum raw string.
    case invalidValue(entity: String, field: String, value: String)

    var description: String {
        switch self {
        case .missingField(let entity, let field):
            "\(entity).\(field) is missing"
        case .invalidValue(let entity, let field, let value):
            "\(entity).\(field) holds invalid value \"\(value)\""
        }
    }

    /// The same fact with the offending VALUE withheld - what goes to the log.
    ///
    /// `description` interpolates `value`, and two throw sites put user
    /// financial content in that slot: `SubscriptionMapping` throws
    /// `"\(lengthDays)/\(bufferDays)/\(convertsTo)"`, where `convertsTo` is a
    /// trial conversion AMOUNT, and `URL.storedOptional` throws the raw string,
    /// reached for `vendorURL` and `cancellationURL` - which vendor.
    ///
    /// `Logger` interpolation defaults to `.private`, so those rendered as
    /// `<private>` on a normal read. That is not the question this project
    /// asks: `OttoLog` states that ".private redaction is a display rule, not a
    /// guarantee about what was written", and a sysdiagnose is readable by
    /// anyone holding the device. The entity and field names are schema
    /// constants, so what remains is safe to mark `.public` - and marking it so
    /// makes the log MORE useful than the redacted form it replaces.
    var logSummary: String {
        switch self {
        case .missingField(let entity, let field):
            "\(entity).\(field) is missing"
        case .invalidValue(let entity, let field, _):
            "\(entity).\(field) holds an invalid value"
        }
    }
}

/// What may be written about an arbitrary error caught at a mapping boundary:
/// a `MappingError`'s value-free summary, or any other error's TYPE name.
/// Never `String(describing:)` of the error itself, which is what carried the
/// amount and the URL into the log.
func mappingLogSummary(_ error: any Error) -> String {
    (error as? MappingError)?.logSummary ?? String(describing: type(of: error))
}

/// Unwraps a required stored field or throws `.missingField`.
func require<Value>(_ value: Value?, entity: String, field: String) throws -> Value {
    guard let value else { throw MappingError.missingField(entity: entity, field: field) }
    return value
}

/// Decodes a stored raw string into a domain enum, throwing on nil or unknown raws -
/// an unknown raw usually means a newer schema wrote it (spec §5.6 stores stable
/// strings precisely so this fails loudly instead of reordering silently).
func decodeRaw<Value: RawRepresentable>(
    _ raw: String?,
    entity: String,
    field: String
) throws -> Value where Value.RawValue == String {
    let raw = try require(raw, entity: entity, field: field)
    guard let value = Value(rawValue: raw) else {
        throw MappingError.invalidValue(entity: entity, field: field, value: raw)
    }
    return value
}
