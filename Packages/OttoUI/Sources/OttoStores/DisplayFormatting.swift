import Foundation
import OttoDomain

// Display formatting for money and days - the only place domain values become
// user-facing strings. Everything goes through Foundation's locale-aware
// formatters; nothing is ever assembled by string interpolation (Wave 3
// constraint), so VoiceOver reads real currencies and real dates.

/// Integer cents as localized currency, e.g. 1099 + "CAD" → "$10.99".
public func currencyText(cents: Int, currencyCode: String, locale: Locale = .current) -> String {
    let amount = Decimal(cents) / 100
    return amount.formatted(.currency(code: currencyCode).locale(locale))
}

/// The monthly-equivalent price as localized currency (spec §7.2's normalisation,
/// rounded only here, at display).
public func monthlyEquivalentText(
    amountCents: Int,
    cycle: BillingCycle,
    currencyCode: String,
    locale: Locale = .current
) -> String {
    currencyText(
        cents: monthlyEquivalentCents(amountCents: amountCents, cycle: cycle),
        currencyCode: currencyCode,
        locale: locale
    )
}

extension CalendarDay {
    /// The day rendered for display in the current calendar - formatting only;
    /// billing arithmetic never touches `Date` (spec §4.1).
    public func displayDate(calendar: Calendar = .current) -> Date? {
        calendar.date(from: dateComponents)
    }

    /// The day as localized text, e.g. "Aug 15, 2026" in en-CA.
    public func displayText(
        style: Date.FormatStyle.DateStyle = .abbreviated,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let date = displayDate(calendar: calendar) else {
            // Unreachable for a valid CalendarDay in the Gregorian calendar; the
            // numeric fallback keeps even an impossible failure legible.
            return "\(year)-\(month)-\(day)"
        }
        return date.formatted(Date.FormatStyle(date: style).locale(locale))
    }
}

/// The friendly cadence name for a cycle, e.g. "Monthly" or "Every 45 days".
public func cycleText(_ cycle: BillingCycle) -> String {
    switch (cycle.unit, cycle.interval) {
    case (.week, 1): String(localized: "Weekly")
    case (.week, 2): String(localized: "Biweekly")
    case (.month, 1): String(localized: "Monthly")
    case (.month, 3): String(localized: "Quarterly")
    case (.month, 6): String(localized: "Semiannual")
    case (.year, 1): String(localized: "Annual")
    case (.day, let interval): String(localized: "Every \(interval) days")
    case (.week, let interval): String(localized: "Every \(interval) weeks")
    case (.month, let interval): String(localized: "Every \(interval) months")
    case (.year, let interval): String(localized: "Every \(interval) years")
    }
}
