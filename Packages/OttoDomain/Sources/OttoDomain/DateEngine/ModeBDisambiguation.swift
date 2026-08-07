// The Mode B disambiguation (spec §5.1). Mode B cannot recover an anchor that
// clamping has already destroyed: "next charge Feb 28" is what a 28th-anchored AND
// a 31st-anchored subscription both show in February, and nothing in the input can
// tell them apart. The one-tap mitigation asks the user - "the last day of the
// month, or specifically the 28th?" - and this is the arithmetic behind the first
// answer.

/// The anchor to store when the user answers "the last day of the month", or nil
/// when the entered date carries no such ambiguity and no question should be asked.
///
/// Non-nil exactly when a month- or year-cycle date is the last day of its month
/// and some earlier cycle month is longer - so an anchor with a larger day number
/// would land on this exact date by clamping (spec §4.2). The returned anchor is
/// that earlier month's last day: for "next charge Feb 28, monthly" it is Jan 31,
/// which bills Feb 28 and then returns to the 31st - while the entered date itself,
/// stored as the anchor, would bill the 28th forever. Both are real occurrences of
/// their sequences, so either answer anchors at a date the sequence actually
/// contains, never at a back-derived fiction.
public func lastDayOfMonthAnchor(forNextBillingDate date: CalendarDay, cycle: BillingCycle) -> CalendarDay? {
    // Day and week cycles have no anchor day and never clamp (spec §4.2 rule 5).
    guard cycle.unit == .month || cycle.unit == .year else { return nil }
    guard date.day == CalendarDay.daysIn(month: date.month, year: date.year) else { return nil }

    let monthsPerCycle = cycle.unit == .year ? cycle.interval * 12 : cycle.interval
    let enteredMonthCount = date.year * 12 + (date.month - 1)

    // Walk earlier cycle months for one longer than the entered month - the nearest
    // such month maximises the anchor day. 48 steps covers every month residue for
    // month cycles and the leap-year period for year cycles; a 31-day month ends the
    // search because no month is longer.
    var best: CalendarDay?
    var bestLength = date.day
    for stepsBack in 1...48 {
        let monthCount = enteredMonthCount - stepsBack * monthsPerCycle
        guard monthCount >= 12 else { break }
        let year = monthCount / 12
        let month = monthCount % 12 + 1
        let length = CalendarDay.daysIn(month: month, year: year)
        if length > bestLength {
            best = CalendarDay(validYear: year, validMonth: month, validDay: length)
            bestLength = length
            if length == 31 { break }
        }
    }
    return best
}
