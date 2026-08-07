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

/// RFC 4180 quoting: fields containing commas, quotes, or line breaks are
/// quoted, with quotes doubled.
private func csvField(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n")
            || value.contains("\r")
    else { return value }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
