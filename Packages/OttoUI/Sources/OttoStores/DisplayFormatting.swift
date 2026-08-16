import Foundation
import OttoDomain

// Display formatting for money and days - the only place domain values become
// user-facing strings. Everything goes through Foundation's locale-aware
// formatters; nothing is ever assembled by string interpolation (Wave 3
// constraint), so VoiceOver reads real currencies and real dates.
//
// Every formatter here honors the REQUESTED locale completely - calendar and
// numbering system included (round 5, item 8 / N2-1). `Date.FormatStyle`
// renders through `Calendar.autoupdatingCurrent` unless told otherwise, and a
// `.locale()` call does not override that, so an explicit en_CA request on a
// Buddhist device read "Aug 15, 2569 BE" - the process's calendar wearing the
// requested locale's month names. The default stays `.current`, so device
// rendering is unchanged: a Buddhist device still renders Buddhist years
// unless a caller explicitly asks for something else.

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
    /// The day as the instant it denotes - formatting only; billing arithmetic
    /// never touches `Date` (spec §4.1).
    ///
    /// The default is `CalendarDay.conversionCalendar`, not `Calendar.current`:
    /// the day's numbers are Gregorian, so resolving them in a device calendar
    /// that numbers years differently yields a `Date` centuries away. The
    /// *rendering* still follows the reader's calendar, because that is the
    /// locale's job downstream, not this conversion's.
    public func displayDate(calendar: Calendar = CalendarDay.conversionCalendar) -> Date? {
        calendar.date(from: dateComponents)
    }

    /// The day as localized text, e.g. "Aug 15, 2026" in en-CA.
    ///
    /// Two calendars, two axes, kept distinct: `calendar` is the day-to-`Date`
    /// CONVERSION calendar (the stored numbers are Gregorian, so it defaults to
    /// the proleptic-Gregorian conversion calendar and must not wander), while
    /// the RENDERING calendar belongs to `locale` - the style below adopts
    /// `locale.calendar`, so an explicit en_CA request reads Gregorian on every
    /// device and `.current` still reads the device's own calendar.
    public func displayText(
        style: Date.FormatStyle.DateStyle = .abbreviated,
        calendar: Calendar = CalendarDay.conversionCalendar,
        locale: Locale = .current
    ) -> String {
        guard let date = displayDate(calendar: calendar) else {
            // Unreachable for a valid CalendarDay in the Gregorian calendar; the
            // numeric fallback keeps even an impossible failure legible.
            return "\(year)-\(month)-\(day)"
        }
        return date.formatted(Date.FormatStyle(date: style, locale: locale, calendar: locale.calendar))
    }
}

extension DisputeSummary {
    /// The dispute, as one paragraph the user can read aloud to a bank or
    /// screenshot (spec §5.4, §7.1 screen 6). Every fact the summary holds, in
    /// sentence form, real formatters throughout.
    public func spokenText(
        calendar: Calendar = CalendarDay.conversionCalendar,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        // `calendar` (the parameter) converts the charge DAY below; the
        // rendering calendar is the requested locale's, same rule as
        // `displayText`.
        let cancelled = markedCancelledAt.formatted(
            Date.FormatStyle(date: .abbreviated, locale: locale, calendar: locale.calendar, timeZone: timeZone)
        )
        let charge = chargeDate.displayText(calendar: calendar, locale: locale)
        let amount = currencyText(cents: chargeAmountCents, currencyCode: currencyCode, locale: locale)
        var lines = [
            String(localized: "I cancelled my \(subscriptionName) subscription on \(cancelled)."),
            String(localized: "A charge of \(amount) was still made on \(charge).")
        ]
        for note in evidenceNotes {
            let noted = note.createdAt.formatted(
                Date.FormatStyle(date: .abbreviated, locale: locale, calendar: locale.calendar, timeZone: timeZone)
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
///
/// The locale governs the interpolated count's numerals as well as the
/// inflection (round 5, item 8): the default `.current` renders "١
/// subscription" on an ar_SA device, and an explicit en_CA request renders
/// "1 subscription" there too.
public func subscriptionCountText(_ count: Int, locale: Locale = .current) -> String {
    String(
        AttributedString(
            localized: "^[\(count) subscription](inflect: true)", locale: locale
        ).characters
    )
}

/// The friendly cadence name for a cycle, e.g. "Monthly" or "Every 45 days".
/// The locale formats the interpolated interval (round 5, item 8): numerals
/// follow the requested locale, not the process's.
public func cycleText(_ cycle: BillingCycle, locale: Locale = .current) -> String {
    switch (cycle.unit, cycle.interval) {
    case (.week, 1): String(localized: "Weekly", locale: locale)
    case (.week, 2): String(localized: "Biweekly", locale: locale)
    case (.month, 1): String(localized: "Monthly", locale: locale)
    case (.month, 3): String(localized: "Quarterly", locale: locale)
    case (.month, 6): String(localized: "Semiannual", locale: locale)
    case (.year, 1): String(localized: "Annual", locale: locale)
    case (.day, let interval): String(localized: "Every \(interval) days", locale: locale)
    case (.week, let interval): String(localized: "Every \(interval) weeks", locale: locale)
    case (.month, let interval): String(localized: "Every \(interval) months", locale: locale)
    case (.year, let interval): String(localized: "Every \(interval) years", locale: locale)
    }
}
