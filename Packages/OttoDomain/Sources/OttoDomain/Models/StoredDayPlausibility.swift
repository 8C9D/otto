import Foundation

// R0-7 / N2-2: detecting stored calendar days that cannot be dates near today.
//
// F1 made every CalendarDay-to-Foundation conversion resolve in the domain's
// own Gregorian calendar. It stops NEW corruption; it repairs none of the days
// a pre-F1 build already wrote through `Calendar.current` on a device set to
// another calendar - and on such a device it makes matters worse. The stored
// anchors are era-numbered (2569 on a Buddhist device), `today` is now 2026,
// every stored date is centuries beyond the 90-day horizon, so NOTHING is
// planned - and `ledgerFailures` stays empty, so Today states coverage through
// the full horizon over zero scheduled reminders.
//
// Measured against the real scheduler rather than reasoned about: an
// era-numbered anchor produced `scheduledCount=0, ledgerFailures=0,
// canClaimCoverage=true, coveredThrough=2026-11-09` - identical on every field
// Today reads to a healthy subscription that scheduled four reminders.
//
// This DETECTS; it does not repair. Repairing means knowing which calendar
// wrote each day, and nothing ever recorded that; PROD-READINESS-3.md ITEM 1
// sets out why no schema marker can supply it after the fact. What detection
// can do is stop such a day passing silently, which is the whole difference
// between a user who can see something is wrong and one who cannot.

extension CalendarDay {

    /// How far from today a stored day may be and still be a date Otto can
    /// schedule against.
    ///
    /// Every calendar Foundation offers numbers its years with an offset of
    /// hundreds of years from the Gregorian ones `CalendarDay` is built on -
    /// Buddhist +543, Hebrew +3760, Islamic -578, Minguo -1911, Japanese Reiwa
    /// -2018, Persian -621. A century separates every one of them from any
    /// billing date a subscription can plausibly carry, and the nearest miss
    /// (Islamic, 578 years) is still five times outside it. Deliberately
    /// generous: this exists to catch a corruption class measured in centuries,
    /// never to second-guess a user who entered an unusual date.
    public static let plausibleStoredDayYears = 100

    /// Whether this day could be a date Otto schedules against, as of `today`.
    ///
    /// Makes NO claim about which calendar wrote the day, and performs no
    /// conversion - both would be guesses, and a guess is not acceptable on
    /// billing dates.
    public func isPlausibleStoredDay(asOf today: CalendarDay) -> Bool {
        abs(year - today.year) <= CalendarDay.plausibleStoredDayYears
    }
}

extension Subscription {

    /// The stored days this subscription schedules against that cannot be dates
    /// near `today` (R0-7 / N2-2), deduplicated and in day order.
    ///
    /// Exactly the fields the planner and the materializer read as days to
    /// schedule against: the stored anchor, the trial's entered start and its
    /// derived conversion date, a pause's scheduled resume, and the last
    /// recorded use (the §7.3 check-in counts from it). An amount, a name or a
    /// URL cannot carry this corruption, and reporting a field nothing
    /// schedules against would name a problem the user cannot act on.
    ///
    /// The stored anchor is read directly rather than through
    /// `billingAnchor(asOf:)`, because that derivation compares the trial's
    /// conversion date against `today` - the very comparison the corruption
    /// breaks - and both of its outcomes are checked here anyway.
    ///
    /// Empty for every subscription on a device that was always Gregorian,
    /// which is the only behaviour this adds there.
    public func implausibleStoredDays(asOf today: CalendarDay) -> [CalendarDay] {
        var candidates: [CalendarDay] = [cycleStartDay]
        if let trial {
            candidates.append(trial.startDate)
            candidates.append(trial.conversionDate)
        }
        if let pauseEndsOn { candidates.append(pauseEndsOn) }
        if let lastUsedDate { candidates.append(lastUsedDate) }
        var seen: Set<CalendarDay> = []
        return candidates
            .filter { !$0.isPlausibleStoredDay(asOf: today) && seen.insert($0).inserted }
            .sorted()
    }
}
