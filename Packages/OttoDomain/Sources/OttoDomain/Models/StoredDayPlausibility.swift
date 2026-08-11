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
    /// MOST calendars Foundation offers number their years hundreds of years
    /// away from the Gregorian ones `CalendarDay` is built on, so a day written
    /// under one and read as Gregorian lands far outside any window a real
    /// billing date occupies. Measured against Foundation rather than asserted
    /// from memory: for one instant, Buddhist writes +543 years, Hebrew +3760,
    /// the four Islamic variants -578, Persian -621, Coptic -284, Minguo -1911,
    /// Chinese -1983, Japanese -2018. A century is inside all of those and
    /// outside any date a user could mean.
    ///
    /// **Two are not catchable this way, and no threshold makes them so.**
    /// Ethiopic writes only **+8** years (2018-11-30 for Gregorian 2026-08-06)
    /// and Indian (Saka) **-78** (1948-05-15). Both land inside any window wide
    /// enough to admit an ordinary long-held subscription, and both leave a
    /// stored triple indistinguishable from a legitimate Gregorian anchor of
    /// that same date. `StoredDayPlausibilityTests` pins that boundary on both
    /// sides rather than leaving it an omission, and `PROD-READINESS-3.md`
    /// ITEM 1 records the measurement showing why the obvious alternative -
    /// cross-checking the stored triple against the record's own `createdAt` -
    /// is not an improvement.
    ///
    /// Deliberately generous within that limit: this catches a corruption class
    /// measured in centuries, and must never second-guess a user who entered an
    /// unusual date.
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
    /// The days a `Subscription` itself carries that the planner and the
    /// materializer schedule against: the stored anchor, the trial's entered
    /// start and its derived conversion date, a pause's scheduled resume, and
    /// the last recorded use (the §7.3 check-in counts from it). An amount, a
    /// name or a URL cannot carry this corruption, and reporting a field
    /// nothing schedules against would name a problem the user cannot act on.
    ///
    /// **Not every stored day the materializer reads.** It also reads the §5.3
    /// materialization watermark, which left the versioned schema in Wave 6A,
    /// lives in the device-state store and is not on this value at all
    /// (`OttoStore+BillingEvents.swift`, `deviceWatermark(for:)`). A corrupt
    /// watermark widens the window without changing the sequence, because
    /// charges are generated from the anchor rather than from the window start
    /// - so it is currently harmless, and it is the wording here, not the code,
    /// that would otherwise be wrong (`reviews-3/REVIEW-2.md` finding 7).
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
