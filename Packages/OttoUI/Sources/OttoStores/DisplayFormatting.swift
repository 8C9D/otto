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

/// The calendar a `CalendarDay`'s numbers are IN.
///
/// `CalendarDay` is proleptic Gregorian by construction - its day arithmetic is
/// an ordinal count anchored at 0001-01-01 (`CalendarDay.ordinalDay`) and its
/// one instant conversion, `fireDate(hour:minute:in:)`, hard-codes
/// `.gregorian`. So resolving a `CalendarDay`'s year/month/day through
/// `Calendar.current` reads Gregorian numbers in whatever calendar the DEVICE
/// is set to, and on a Buddhist device "2026-08-06" is read as year 2026 of the
/// Buddhist era. Every day/instant conversion goes through this, and none of
/// them takes a calendar parameter, so there is no seam left to get it wrong.
///
/// This is not a display choice. Rendering stays locale-aware: the instant is
/// resolved here in Gregorian, and the formatter that prints it still shows it
/// in the reader's own calendar.
public let ottoDayCalendar = Calendar(identifier: .gregorian)

extension CalendarDay {
    /// The instant at which this calendar day begins, in the device's timezone.
    /// Formatting only; billing arithmetic never touches `Date` (spec §4.1).
    public func displayDate() -> Date? {
        var calendar = ottoDayCalendar
        calendar.timeZone = .current
        return calendar.date(from: dateComponents)
    }

    /// The day as localized text, e.g. "Aug 15, 2026" in en-CA.
    public func displayText(
        style: Date.FormatStyle.DateStyle = .abbreviated,
        locale: Locale = .current
    ) -> String {
        guard let date = displayDate() else {
            // Unreachable for a valid CalendarDay in the Gregorian calendar; the
            // numeric fallback keeps even an impossible failure legible.
            return "\(year)-\(month)-\(day)"
        }
        return date.formatted(Date.FormatStyle(date: style).locale(locale))
    }
}

extension DisputeSummary {
    /// The dispute, as one paragraph the user can read aloud to a bank or
    /// screenshot (spec §5.4, §7.1 screen 6). Every fact the summary holds, in
    /// sentence form, real formatters throughout.
    public func spokenText(
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let cancelled = markedCancelledAt.formatted(
            Date.FormatStyle(date: .abbreviated, timeZone: timeZone).locale(locale)
        )
        let charge = chargeDate.displayText(locale: locale)
        let amount = currencyText(cents: chargeAmountCents, currencyCode: currencyCode, locale: locale)
        var lines = [
            String(localized: "I cancelled my \(subscriptionName) subscription on \(cancelled)."),
            String(localized: "A charge of \(amount) was still made on \(charge).")
        ]
        for note in evidenceNotes {
            let noted = note.createdAt.formatted(
                Date.FormatStyle(date: .abbreviated, timeZone: timeZone).locale(locale)
            )
            lines.append(String(localized: "Cancellation evidence (\(noted)): \(note.text)."))
        }
        lines.append(String(localized: "I am disputing this charge."))
        return lines.joined(separator: "\n")
    }
}

/// "1 subscription" / "3 subscriptions" - the count phrase with its
/// `^[...](inflect: true)` morphology markup actually RESOLVED (Wave 10,
/// defect I). `Text(String(localized:))` performs no inflection - the raw
/// markup rendered literally on the Payment-methods screen - so every
/// count-inflected phrase routes through here, where `AttributedString`'s
/// localized initializer runs the grammar engine, and a test asserts the
/// rendered string carries no markup residue. Nouns only: the engine does not
/// conjugate English verbs, so surrounding copy must stay number-invariant.
public func subscriptionCountText(_ count: Int) -> String {
    String(AttributedString(localized: "^[\(count) subscription](inflect: true)").characters)
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
