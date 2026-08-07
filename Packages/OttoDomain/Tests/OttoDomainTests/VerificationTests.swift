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
        #expect(verificationCheckDate(for: daily, asOf: try day(2026, 12, 25)) == (try day(2027, 1, 4)))

        // Weekly from a Friday.
        let weekly = try makeSubscription(
            status: .active, cycle: .weekly, cycleStartDay: try day(2026, 8, 7)
        )
        #expect(verificationCheckDate(for: weekly, asOf: try day(2026, 8, 10)) == (try day(2026, 8, 14)))

        // Monthly - the required case: a 31-anchored subscription cancelled in
        // February lands on Feb 28, the clamp, not March.
        let monthly = try makeSubscription(
            status: .active, cycle: .monthly, cycleStartDay: try day(2026, 1, 31)
        )
        #expect(verificationCheckDate(for: monthly, asOf: try day(2026, 2, 10)) == (try day(2026, 2, 28)))
        // And the clamp does not leak: cancelled in March, the check is Mar 31.
        #expect(verificationCheckDate(for: monthly, asOf: try day(2026, 3, 1)) == (try day(2026, 3, 31)))

        // Annual.
        let annual = try makeSubscription(
            status: .active, cycle: .annual, cycleStartDay: try day(2026, 3, 15)
        )
        #expect(verificationCheckDate(for: annual, asOf: try day(2026, 6, 1)) == (try day(2027, 3, 15)))
    }

    @Test("a charge landing today counts - cancelling on the charge day watches today, not next cycle")
    func todayCounts() throws {
        let subscription = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 15)) == (try day(2026, 8, 15)))
    }

    @Test("a trial cancelled before converting is checked on its conversion date - the first would-be charge")
    func unconvertedTrialChecksConversion() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 27), lengthDays: 14)
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 27), trial: trial
        )
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 6)) == trial.conversionDate)
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
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 5)) == (try day(2026, 8, 31)))
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

@Suite("Verification transitions (spec §5.4)")
struct VerificationTransitionTests {

    private let now = Date(timeIntervalSince1970: 10_000)
    private let later = Date(timeIntervalSince1970: 20_000)

    @Test("the yes-path verifies, the no-path disputes, and both keep their first answer instant")
    func answersAreIdempotent() throws {
        let record = try makeCancellationRecord(
            subscriptionID: try fixtureUUID(1), nextChargeDateIfNotCancelled: try day(2026, 8, 20)
        )

        let stopped = record.confirmingChargesStopped(at: now)
        #expect(stopped.verificationState == .verifiedStopped)
        #expect(stopped.verifiedAt == now)
        #expect(stopped.confirmingChargesStopped(at: later) == stopped)

        let charging = record.reportingStillCharging(at: now)
        #expect(charging.verificationState == .stillCharging)
        #expect(charging.verifiedAt == now)
        #expect(charging.reportingStillCharging(at: later) == charging)
    }

    @Test("answers are accepted from the escalated state too - the persistent card exists to be answered")
    func answersFromNeedsManualReview() throws {
        let escalated = try makeCancellationRecord(
            subscriptionID: try fixtureUUID(1),
            nextChargeDateIfNotCancelled: try day(2026, 8, 20),
            verificationState: .needsManualReview
        )
        #expect(escalated.confirmingChargesStopped(at: now).verificationState == .verifiedStopped)
        #expect(escalated.reportingStillCharging(at: now).verificationState == .stillCharging)
    }

    @Test("each passed check date increments the counter and rolls the watch forward one cycle")
    func rollForwardSingleCycle() throws {
        let subscription = try makeSubscription(status: .cancelled, cycleStartDay: try day(2026, 1, 15))
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 8, 15)
        )

        // The day after the unanswered check: one increment, one roll.
        let rolled = record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 16), at: now
        )
        #expect(rolled.unansweredCheckCount == 1)
        #expect(rolled.nextChargeDateIfNotCancelled == (try day(2026, 9, 15)))
        #expect(rolled.verificationState == .pending)

        // Same day again: nothing left to catch up - running twice equals once.
        #expect(rolled.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 16), at: later
        ) == rolled)
    }

    @Test("a check dated today is still answerable today - it does not roll")
    func todayDoesNotRoll() throws {
        let subscription = try makeSubscription(status: .cancelled, cycleStartDay: try day(2026, 1, 15))
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 8, 15)
        )
        #expect(record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 15), at: now
        ) == record)
    }

    @Test("a long absence catches up in one call and stops at exactly three: .needsManualReview, date frozen")
    func threeStrikesEscalates() throws {
        let subscription = try makeSubscription(status: .cancelled, cycleStartDay: try day(2026, 1, 15))
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 8, 15)
        )

        // Opened again Dec 20: Aug 15, Sep 15, Oct 15 all passed unanswered. The
        // count stops at exactly three even though Nov 15 passed too, and the
        // record escalates instead of rolling further.
        let escalated = record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 12, 20), at: now
        )
        #expect(escalated.unansweredCheckCount == 3)
        #expect(escalated.verificationState == .needsManualReview)
        #expect(escalated.nextChargeDateIfNotCancelled == (try day(2026, 11, 15)))

        // Escalation is terminal for the catch-up: more passing time changes nothing.
        #expect(escalated.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2027, 3, 1), at: later
        ) == escalated)
    }

    @Test("an answered record never rolls - the watch ended with the answer")
    func answeredRecordsDoNotRoll() throws {
        let subscription = try makeSubscription(status: .cancelled, cycleStartDay: try day(2026, 1, 15))
        for state in [CancellationRecord.VerificationState.verifiedStopped, .stillCharging] {
            let record = try makeCancellationRecord(
                subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 8, 15),
                verificationState: state
            )
            #expect(record.catchingUpOnUnansweredChecks(
                for: subscription, asOf: try day(2027, 1, 1), at: now
            ) == record)
        }
    }

    @Test("a cancelled trial rolls along the conversion-anchored paid sequence")
    func trialRollsFromConversionAnchor() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30)
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        // Watching the conversion charge (Jul 31); it passes unanswered. The next
        // would-be charge is Aug 31 - the paid cycle from the conversion anchor.
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: trial.conversionDate
        )
        let rolled = record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 3), at: now
        )
        #expect(rolled.unansweredCheckCount == 1)
        #expect(rolled.nextChargeDateIfNotCancelled == (try day(2026, 8, 31)))
    }

    @Test("the watched amount moves with the watched date (spec §5.4, v1.5)")
    func rollUpdatesAmount() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599)
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        // The stored amount has gone stale relative to the date it watches; the
        // roll to Aug 31 - a post-conversion date - re-derives it in step.
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: trial.conversionDate,
            expectedChargeAmountCents: 1099
        )
        let rolled = record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 3), at: now
        )
        #expect(rolled.nextChargeDateIfNotCancelled == (try day(2026, 8, 31)))
        #expect(rolled.expectedChargeAmountCents == 1599)
    }

    @Test("a pre-v1.5 record's missing amount is backfilled by the roll-forward, even when nothing rolls")
    func backfillsMissingAmount() throws {
        let subscription = try makeSubscription(status: .cancelled, cycleStartDay: try day(2026, 1, 15))
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            expectedChargeAmountCents: nil
        )

        let backfilled = record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 15), at: now
        )
        #expect(backfilled.expectedChargeAmountCents == subscription.amountCents)
        #expect(backfilled.nextChargeDateIfNotCancelled == record.nextChargeDateIfNotCancelled)
        #expect(backfilled.unansweredCheckCount == 0)

        // And the backfill is once: a second pass changes nothing.
        #expect(backfilled.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2026, 8, 15), at: later
        ) == backfilled)
    }
}

@Suite("The dispute summary (spec §5.4)")
struct DisputeSummaryTests {

    @Test("a .stillCharging record yields the full dispute: cancellation instant, evidence, charge date and amount")
    func populatedSummary() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1100)
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        var record = try makeCancellationRecord(
            subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 8, 31),
            expectedChargeAmountCents: 1100
        )
        record.evidenceNote = "confirmation #4821, spoke to Dana"
        let answered = record.reportingStillCharging(at: Date(timeIntervalSince1970: 10_000))

        let summary = try #require(disputeSummary(for: answered, subscription: subscription))
        #expect(summary.subscriptionName == subscription.name)
        #expect(summary.markedCancelledAt == record.markedCancelledAt)
        #expect(summary.evidenceNote == "confirmation #4821, spoke to Dana")
        #expect(summary.chargeDate == (try day(2026, 8, 31)))
        #expect(summary.chargeAmountCents == 1100)
        #expect(summary.currencyCode == "CAD")
    }

    @Test("the summary reports the amount stored at cancellation, not one derived from the edited price (spec §5.4, v1.5)")
    func storedAmountBeatsDerivation() throws {
        // Cancelled while the price was 1399; the user then hand-edited the
        // price to 1099. The derivation can only see the edited price - the
        // stored amount is the record of what the vendor would actually charge,
        // and the summary that ends at a bank must not infer.
        let subscription = try makeSubscription(status: .cancellationPending, cycleStartDay: try day(2026, 1, 15))
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            expectedChargeAmountCents: 1399,
            verificationState: .stillCharging
        )
        let summary = try #require(disputeSummary(for: record, subscription: subscription))
        #expect(summary.chargeAmountCents == 1399)

        // Only a pre-v1.5 record - amount never captured, never backfilled -
        // falls back to the derivation.
        let legacy = try makeCancellationRecord(
            subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            expectedChargeAmountCents: nil,
            verificationState: .stillCharging
        )
        let legacySummary = try #require(disputeSummary(for: legacy, subscription: subscription))
        #expect(legacySummary.chargeAmountCents == subscription.amountCents)
    }

    @Test("no dispute exists before a charge was reported", arguments: [
        CancellationRecord.VerificationState.pending, .verifiedStopped, .needsManualReview
    ])
    func noSummaryWithoutFailure(state: CancellationRecord.VerificationState) throws {
        let subscription = try makeSubscription(status: .cancelled, cycleStartDay: try day(2026, 1, 15))
        let record = try makeCancellationRecord(
            subscriptionID: subscription.id,
            nextChargeDateIfNotCancelled: try day(2026, 8, 15),
            verificationState: state
        )
        #expect(disputeSummary(for: record, subscription: subscription) == nil)
    }
}

@Suite("Confirming a trial conversion (spec §5.2a)")
struct ConversionConfirmationTests {

    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("confirming flips to active on the paid sequence and RETAINS the trial - it records, never deletes")
    func confirmingFlips() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599)
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 1), trial: trial
        )

        let flipped = try #require(subscription.confirmingConversion(asOf: try day(2026, 8, 5), at: now))
        #expect(flipped.storedStatus == .active)
        #expect(flipped.cycleStartDay == trial.conversionDate)
        #expect(flipped.amountCents == 1599)
        #expect(flipped.trial == trial)
        #expect(flipped.updatedAt == now)
        #expect(flipped.id == subscription.id)
        #expect(flipped.createdAt == subscription.createdAt)

        // The flip changes no behaviour, only persists it: the effective values
        // before and the stored values after are the same schedule (spec §5.2a).
        let today = try day(2026, 8, 5)
        #expect(flipped.billingAnchor(asOf: today) == subscription.billingAnchor(asOf: today))
        #expect(flipped.billingAmountCents(asOf: today) == subscription.billingAmountCents(asOf: today))
        #expect(flipped.effectiveStatus(asOf: today) == subscription.effectiveStatus(asOf: today))
    }

    @Test("nothing to confirm before conversion, after a flip, or without a trial")
    func confirmingIsGuarded() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 30)
        let unconverted = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        #expect(unconverted.confirmingConversion(asOf: try day(2026, 7, 20), at: now) == nil)

        let flipped = try #require(unconverted.confirmingConversion(asOf: try day(2026, 8, 5), at: now))
        #expect(flipped.confirmingConversion(asOf: try day(2026, 8, 5), at: now) == nil)

        let plain = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 15))
        #expect(plain.confirmingConversion(asOf: try day(2026, 8, 5), at: now) == nil)
    }
}
