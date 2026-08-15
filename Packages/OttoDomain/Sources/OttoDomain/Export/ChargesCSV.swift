import Foundation

// The human-readable export (Wave 8): the charge ledger as a spreadsheet,
// because "open it in Numbers to check a figure" means checking a charge. This
// is deliberately LOSSY and one-way - no ids, no tombstones, no trial terms -
// and the UI says so; the JSON export is the format that round-trips.

/// The ledger as RFC 4180 CSV, one row per live billing event, joined with the
/// subscription's name and sorted by date then name so the newest activity is
/// at the bottom the way a statement reads.
///
/// Amounts are exact decimal strings derived from integer cents - "10.99" is
/// string arithmetic, not floating point.
public func chargesCSV(from snapshot: OttoDataSnapshot) -> String {
    let namesByID = Dictionary(
        uniqueKeysWithValues: snapshot.subscriptions.map { ($0.id, $0.name) }
    )
    let currenciesByID = Dictionary(
        uniqueKeysWithValues: snapshot.subscriptions.map { ($0.id, $0.currencyCode) }
    )
    let liveSubscriptionIDs = Set(
        snapshot.subscriptions.filter { $0.deletedAt == nil }.map(\.id)
    )

    let header = "date,subscription,state,expected amount,actual amount,currency"
    let rows = snapshot.billingEvents
        .filter { $0.deletedAt == nil && liveSubscriptionIDs.contains($0.subscriptionID) }
        .sorted {
            ($0.expectedDate, namesByID[$0.subscriptionID] ?? "", $0.id.uuidString)
                < ($1.expectedDate, namesByID[$1.subscriptionID] ?? "", $1.id.uuidString)
        }
        .map { event in
            [
                event.expectedDate.description,
                csvField(namesByID[event.subscriptionID] ?? ""),
                csvField(stateText(event.state)),
                decimalAmount(cents: event.expectedAmountCents),
                event.actualAmountCents.map(decimalAmount(cents:)) ?? "",
                csvField(currenciesByID[event.subscriptionID] ?? "")
            ].joined(separator: ",")
        }
    return ([header] + rows).joined(separator: "\r\n") + "\r\n"
}

/// Cents as an exact decimal string: 1099 -> "10.99", -50 -> "-0.50".
func decimalAmount(cents: Int) -> String {
    let sign = cents < 0 ? "-" : ""
    let magnitude = abs(cents)
    return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
}

private func stateText(_ state: BillingEvent.State) -> String {
    switch state {
    case .upcoming: "expected"
    case .confirmedCharged: "charged"
    case .confirmedNotCharged: "not charged"
    case .unexpectedCharge: "unexpected charge"
    case .skipped: "skipped"
    }
}

/// A field, neutralized against formula injection and then RFC 4180 quoted.
///
/// The order matters: the prefix goes on first, so a hostile name that also
/// contains a comma is quoted around the neutralized text rather than beside it.
private func csvField(_ value: String) -> String {
    rfc4180Quoted(withoutLeadingFormula(value))
}

/// The characters a spreadsheet reads as "this cell is a formula" when they
/// begin a cell (F9).
///
/// `=` and `+` start a formula in Excel, Numbers, LibreOffice and Sheets; `@`
/// starts one in Excel and is the legacy Lotus form; `-` starts one wherever a
/// leading minus is not immediately a number, which is what makes
/// `-2+3+cmd|' /C calc'!A0` a command and not a negative amount. Tab, carriage
/// return and newline are here because several importers strip a leading one
/// and then evaluate what is behind it - and the rule stated has to be the rule
/// implemented, which is why `\n` is present: `reviews-4/REVIEW-1.md` finding 8
/// noted it was covered by the sentence and absent from the set.
private let csvFormulaTriggers: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "\n"]

/// F9. Only the export's THREE text fields reach this - the subscription name,
/// the state word and the currency code - and only the first is user-controlled.
/// A user who names a subscription `=HYPERLINK(...)` or `-2+3+cmd|' /C calc'!A0`
/// gets those exact characters back out of the export at HEAD; opened in a
/// spreadsheet they are a formula, and the `cmd|...!A0` shape is a DDE request
/// to run a program. Measured before this existed, by exporting a snapshot of
/// five hostile names: every one came back byte-for-byte.
///
/// The neutralizer is a leading apostrophe, which every spreadsheet reads as
/// "the rest of this cell is text". It is deliberately applied to the CELL and
/// not to the stored name: nothing about the subscription changes, and this
/// export is already documented as lossy and one-way, so a display-level
/// apostrophe in a file meant for reading is the cheap side of the trade. The
/// JSON export - the one that round-trips - is untouched and still carries the
/// exact name.
///
/// Amounts do NOT come through here. `decimalAmount` writes `-0.50` for a
/// negative amount and a leading minus in front of a number is a number to
/// every spreadsheet, so quoting it would corrupt the column this file exists
/// to let someone add up.
private func withoutLeadingFormula(_ value: String) -> String {
    guard let first = value.first, csvFormulaTriggers.contains(first) else { return value }
    return "'\(value)"
}

/// RFC 4180 quoting: fields containing commas, quotes, or line breaks are
/// quoted, with quotes doubled.
private func rfc4180Quoted(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n")
            || value.contains("\r")
    else { return value }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
