import Foundation
import Testing
@testable import OttoDomain

@Suite("Verification check dates (spec §5.4)")
struct VerificationCheckDateTests {

    @Test("the check date is the next would-be charge for every cycle unit")
    func allFourCycleUnits() throws {
        // Daily (every 45 days from Nov 20: Jan 4 crosses the year boundary).
        let daily = try makeSubscription(
            status: .active, cycle: try cycle(.day, 45), cycleStartDay: try day(2026, 11, 20)
        )
        #expect(verificationCheckDate(for: daily, cancelledOn: try day(2026, 12, 25)) == (try day(2027, 1, 4)))

        // Weekly from a Friday.
        let weekly = try makeSubscription(
            status: .active, cycle: .weekly, cycleStartDay: try day(2026, 8, 7)
        )
        #expect(verificationCheckDate(for: weekly, cancelledOn: try day(2026, 8, 10)) == (try day(2026, 8, 14)))

        // Monthly - the required case: a 31-anchored subscription cancelled in
        // February lands on Feb 28, the clamp, not March.
        let monthly = try makeSubscription(
            status: .active, cycle: .monthly, cycleStartDay: try day(2026, 1, 31)
        )
        #expect(verificationCheckDate(for: monthly, cancelledOn: try day(2026, 2, 10)) == (try day(2026, 2, 28)))
        // And the clamp does not leak: cancelled in March, the check is Mar 31.
        #expect(verificationCheckDate(for: monthly, cancelledOn: try day(2026, 3, 1)) == (try day(2026, 3, 31)))

        // Annual.
        let annual = try makeSubscription(
            status: .active, cycle: .annual, cycleStartDay: try day(2026, 3, 15)
        )
        #expect(verificationCheckDate(for: annual, cancelledOn: try day(2026, 6, 1)) == (try day(2027, 3, 15)))
    }

    // The Wave 10 defect-G table: `nextChargeDateIfNotCancelled` is the first
    // occurrence STRICTLY AFTER the cancellation day. An occurrence on the
    // cancellation day already landed legitimately; watching it makes both
    // verification answers meaningless and corrupts the dispute summary - the
    // one output with an external audience.

    @Test("⛔ cancelling on the conversion day watches the NEXT cycle - the conversion charge already landed")
    func cancelOnConversionDayWatchesNextCycle() throws {
        // The Gate Test case verbatim: trial started Jul 27, 14 days, converts
        // Aug 10, cancelled ON Aug 10. The Aug 10 charge is the conversion
        // charge, legitimate and pre-cancellation; the check is Sep 10.
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 27), trial: trial
        )
        #expect(trial.conversionDate == (try day(2026, 8, 10)))
        #expect(verificationCheckDate(for: subscription, cancelledOn: try day(2026, 8, 10))
            == (try day(2026, 9, 10)))
    }

    @Test("cancelling on a plain charge day watches the next cycle, not the charge that landed today")
    func cancelOnChargeDayWatchesNextCycle() throws {
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))
        #expect(verificationCheckDate(for: subscription, cancelledOn: try day(2026, 8, 15))
            == (try day(2026, 9, 15)))
    }

    @Test("cancelling mid-cycle watches the next occurrence")
    func cancelMidCycleWatchesNextOccurrence() throws {
        // Sequence Aug 10, Sep 10, ... cancelled Aug 15: the check is Sep 10.
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 8, 10))
        #expect(verificationCheckDate(for: subscription, cancelledOn: try day(2026, 8, 15))
            == (try day(2026, 9, 10)))
    }

    @Test("a trial cancelled before converting is checked on its conversion date - the first charge that would land")
    func unconvertedTrialChecksConversion() throws {
        // Cancelled Aug 5, conversion Aug 10: the conversion charge is the
        // first occurrence strictly after the cancellation day - correct to
        // watch, because it is the charge that lands if the cancellation failed.
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 27), trial: trial
        )
        #expect(verificationCheckDate(for: subscription, cancelledOn: try day(2026, 8, 5)) == trial.conversionDate)
    }

    @Test("cancelling before the anchor watches the anchor - the first occurrence of the sequence")
    func cancelBeforeAnchorWatchesAnchor() throws {
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 8, 10))
        #expect(verificationCheckDate(for: subscription, cancelledOn: try day(2026, 7, 1))
            == (try day(2026, 8, 10)))
    }

    @Test("the cancellation-day conversion is timezone-correct: one instant, two zones, two check dates")
    func cancellationDayIsTimezoneCorrect() throws {
        // 2026-08-16 02:30 UTC is still Aug 15 in Toronto and already Aug 16 in
        // Tokyo - and Aug 16 is an occurrence of this 16th-anchored monthly, so
        // the instant straddles midnight ACROSS a charge day: whether that
        // charge is "already landed" depends entirely on which calendar day the
        // instant converts to.
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 16))
        let instant = try #require(instantUTC(2026, 8, 16, hour: 2, minute: 30))

        let torontoDay = try #require(calendarDay(of: instant, in: "America/Toronto"))
        let tokyoDay = try #require(calendarDay(of: instant, in: "Asia/Tokyo"))
        #expect(torontoDay == (try day(2026, 8, 15)))
        #expect(tokyoDay == (try day(2026, 8, 16)))

        // Toronto: Aug 16 is still ahead, so it is the first occurrence
        // strictly after the cancellation day. Tokyo: Aug 16 IS the
        // cancellation day - that charge lands legitimately - so the watch
        // moves to Sep 16. Same instant, different days, different checks.
        #expect(verificationCheckDate(for: subscription, cancelledOn: torontoDay) == (try day(2026, 8, 16)))
        #expect(verificationCheckDate(for: subscription, cancelledOn: tokyoDay) == (try day(2026, 9, 16)))
    }

    @Test("a converted trial's would-be charges run from the CONVERSION anchor, not the trial start")
    func convertedTrialUsesConversionAnchor() throws {
        // Trial Jul 1-31, monthly. Cancelled Aug 5, converted but never flipped:
        // the stored status was overwritten by the cancellation, so only the
        // trial term knows the paid sequence runs from Jul 31. The next would-be
        // charge is Aug 31 - anchoring at the Jul 1 trial start would say Sep 1.
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30)
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        #expect(verificationCheckDate(for: subscription, cancelledOn: try day(2026, 8, 5)) == (try day(2026, 8, 31)))
    }

    @Test("a would-be charge on or after conversion costs the converted amount for an unflipped trial")
    func wouldBeAmounts() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599)
        let unflipped = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        // amountCents (1099) is the trial-era price; the charge that would land is the converted one.
        #expect(wouldBeChargeAmountCents(on: try day(2026, 8, 31), for: unflipped) == 1599)

        // A flipped subscription's anchor IS the conversion date, and amountCents
        // is current truth - including a later manual price edit.
        let flipped = try makeSubscription(
            status: .cancellationPending, cycleStartDay: trial.conversionDate, trial: trial
        )
        #expect(wouldBeChargeAmountCents(on: try day(2026, 8, 31), for: flipped) == 1099)

        let plain = try makeSubscription(status: .cancellationPending, cycleStartDay: try day(2026, 1, 15))
        #expect(wouldBeChargeAmountCents(on: try day(2026, 8, 15), for: plain) == 1099)
    }
}

@Suite("Dispute summary property (Wave 10, defect G)")
struct DisputeSummaryPropertyTests {

    /// The property §5.4 exists for, stated over every reachable state rather
    /// than a scenario: a dispute summary's charge date is STRICTLY AFTER its
    /// cancellation day. "A charge on the day of cancellation is not evidence
    /// that a cancellation failed" - a bank rejects that on sight, so no
    /// reachable state may produce it.
    ///
    /// Reachable means: an episode opened by `openingCancellationEpisode` on a
    /// real subscription shape, optionally rolled forward by the §5.4
    /// catch-up, then answered still-charging. The grid crosses subscription
    /// shapes with cancellation days on, before, and after an occurrence, and
    /// answers at several later days.
    @Test("every reachable dispute summary's charge date is strictly after its cancellation day")
    func chargeDateStrictlyAfterCancellationDay() throws {
        let timeZoneID = "America/Toronto"
        let timeZone = try #require(TimeZone(identifier: timeZoneID))
        let anchor = try day(2026, 8, 10)
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscriptions: [Subscription] = [
            try makeSubscription(index: 1, status: .active, cycleStartDay: anchor),
            try makeSubscription(index: 2, status: .active, cycle: .weekly, cycleStartDay: anchor),
            try makeSubscription(index: 3, status: .active, cycle: .annual, cycleStartDay: anchor),
            // The Gate Test shape: trial converting Aug 10, stored status
            // never flipped.
            try makeSubscription(
                index: 4, status: .trial, cycleStartDay: try day(2026, 7, 27), trial: trial
            ),
            try makeSubscription(
                index: 5, status: .paused, cycleStartDay: anchor, pauseEndsOn: try day(2026, 9, 1)
            )
        ]
        // On the shared occurrence day, straddling it, and far from it.
        let cancellationDays = [
            try day(2026, 8, 10), try day(2026, 8, 9), try day(2026, 8, 11),
            try day(2026, 7, 1), try day(2026, 12, 31)
        ]
        for subscription in subscriptions {
            for cancellationDay in cancellationDays {
                // `now` is the instant whose calendar day, in the timezone the
                // caller used, IS the cancellation day - the pairing the
                // DateProvider guarantees in production.
                let now = try #require(cancellationDay.fireDate(hour: 12, minute: 0, in: timeZone))
                guard let opened = subscription.openingCancellationEpisode(
                    id: try fixtureUUID(900), evidence: nil, asOf: cancellationDay, at: now
                ) else { continue }
                // Answer immediately, and after absences that roll the watch.
                for answerDelay in [0, 40, 400] {
                    let answerDay = cancellationDay.adding(days: answerDelay)
                    let caughtUp = opened.catchingUpOnUnansweredChecks(
                        for: subscription, asOf: answerDay, at: now
                    )
                    let answered = caughtUp.reportingStillCharging(at: now)
                    guard let summary = disputeSummary(for: answered, subscription: subscription) else {
                        continue
                    }
                    let cancelledDay = try #require(
                        calendarDay(of: summary.markedCancelledAt, in: timeZoneID)
                    )
                    #expect(
                        summary.chargeDate > cancelledDay,
                        "\(subscription.name) cancelled \(cancellationDay), answered +\(answerDelay)d"
                    )
                    // The paused composition (spec §5.4, v1.5 + Wave 10): the
                    // watch also never lands inside the pause.
                    if subscription.storedStatus == .paused, let resumes = subscription.pauseEndsOn,
                       cancellationDay < resumes {
                        #expect(summary.chargeDate >= resumes)
                    }
                }
            }
        }
    }
}
