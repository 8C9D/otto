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
//
// Round 4 (N3-1) made the window ASYMMETRIC, which closes Indian/Saka. The
// twelve corrupting calendars other than Ethiopic are now all detected; the
// measurement and the reason Ethiopic is not are on the two constants below.

extension CalendarDay {

    /// How far AHEAD of today a stored day may be and still be a date Otto can
    /// schedule against.
    ///
    /// Only two calendars write a year larger than the Gregorian one - Buddhist
    /// +543 and Hebrew +3760 - and both are five times outside this. Nothing
    /// forces it tighter, and tightening it would start rejecting a distant
    /// `pauseEndsOn` or a long custom cycle, which are real dates a user chose.
    public static let plausibleStoredDayYearsAhead = 100

    /// How far BEHIND today a stored day may be.
    ///
    /// **Asymmetric, and that is the whole of what round 4 changed here.**
    /// Round 3 used a single symmetric century and recorded Ethiopic and Indian
    /// as unreachable by any threshold. Measured over every day of a year
    /// against Foundation, the year gap each calendar produces is:
    ///
    ///     buddhist  [ +543,  +543]   hebrew   [+3760, +3761]
    ///     chinese   [-1984, -1983]   coptic   [ -284,  -283]
    ///     islamic{,Civil,Tabular,UmmAlQura}   [ -579,  -578]
    ///     japanese  [-2018, -2018]   persian  [ -622,  -621]
    ///     republicOfChina [-1911, -1911]
    ///     indian    [  -79,   -78]   <- reachable, and this is why
    ///     ethiopicAmeteMihret [ -8,   -7]   <- still not reachable
    ///
    /// Indian (Saka) is 78 or 79 years behind, always, in every month and for
    /// every field. Seventy leaves eight years of margin against it and still
    /// accepts a stored day back to 1956 - and the oldest date anything in this
    /// app could sensibly mean is a subscription's cycle origin, which no
    /// consumer subscription has before about 1970. Round 3's own doc comment
    /// named "forty years beyond the oldest plausible billing anchor" as its
    /// justification for a century, which is the same judgment reaching the
    /// same place from the other side.
    ///
    /// **Ethiopic is genuinely unreachable and stays so.** It writes only 7 or
    /// 8 years behind, and a stored day eight years old is an ordinary anchor
    /// for a subscription somebody has held since 2018. `PROD-READINESS-4.md`
    /// ITEM 3 records what was measured about the alternative - cross-checking
    /// the stored triple against the record's own `createdAt` - and why it is
    /// not adopted: its sensitivity is 13/13 only when the stored day is within
    /// K days of the instant the record was created, and 0/13 for every
    /// realistic `lastUsedDate` or distant `pauseEndsOn`.
    public static let plausibleStoredDayYearsBehind = 70

    /// Whether this day could be a date Otto schedules against, as of `today`.
    ///
    /// Makes NO claim about which calendar wrote the day, and performs no
    /// conversion - both would be guesses, and a guess is not acceptable on
    /// billing dates.
    public func isPlausibleStoredDay(asOf today: CalendarDay) -> Bool {
        today.year - year <= CalendarDay.plausibleStoredDayYearsBehind
            && year - today.year <= CalendarDay.plausibleStoredDayYearsAhead
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
