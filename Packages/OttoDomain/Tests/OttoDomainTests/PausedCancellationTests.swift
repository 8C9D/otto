import Foundation
import Testing
@testable import OttoDomain

// Spec §5.4 (v1.5, built in Wave 7): cancelling a paused subscription. The
// check date comes from the resumed sequence, not the plain anchor sequence -
// the vendor is not charging during the pause, so "no charge arrived" on one of
// those dates would prove nothing. With no resume date the check DEFERS: Otto
// never guesses, because a verification answered against a fabricated date
// produces false confidence exactly where the product promises certainty.

@Suite("Cancelling a paused subscription (spec §5.4)")
struct PausedCancellationCheckDateTests {

    @Test("with a pauseEndsOn, the check date is the first occurrence on or after it")
    func datedPauseChecksFirstResumedCharge() throws {
        // Monthly on the 15th, paused until Sep 1: the first would-be charge
        // after resume is Sep 15, not the Aug 15 the plain sequence would name.
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: try day(2026, 9, 1)
        )
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 6)) == (try day(2026, 9, 15)))
    }

    @Test("a resume day that IS an occurrence is itself the check date")
    func resumeDayOnOccurrence() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: try day(2026, 9, 15)
        )
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 6)) == (try day(2026, 9, 15)))
    }

    @Test("with no resume date there is no check date - nil, never a guess")
    func indefinitePauseDefers() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: nil
        )
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 6)) == nil)
    }

    @Test("a pause already past its end date is effectively active and checks normally")
    func resumedPauseChecksNormally() throws {
        let subscription = try makeSubscription(
            status: .paused, cycleStartDay: try day(2026, 1, 15), pauseEndsOn: try day(2026, 7, 1)
        )
        // Derived active as of Aug 6 (spec §5.2a, v1.6): next charge Aug 15.
        #expect(verificationCheckDate(for: subscription, asOf: try day(2026, 8, 6)) == (try day(2026, 8, 15)))
    }
}

@Suite("The deferred verification record (spec §5.4)")
struct DeferredVerificationRecordTests {

    private let now = Date(timeIntervalSince1970: 10_000)

    private func deferredRecord(subscriptionID: UUID) throws -> CancellationRecord {
        CancellationRecord(
            id: try fixtureUUID(601),
            subscriptionID: subscriptionID,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: nil,
            verificationState: .awaitingResumeDate,
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )
    }

    @Test("supplying the resume date starts the watch at the first occurrence on or after it")
    func supplyingResumeDate() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let record = try deferredRecord(subscriptionID: subscription.id)

        let supplied = record.supplyingResumeDate(try day(2026, 9, 1), for: subscription, at: now)

        #expect(supplied.verificationState == .pending)
        #expect(supplied.nextChargeDateIfNotCancelled == (try day(2026, 9, 15)))
        #expect(supplied.expectedChargeAmountCents == subscription.amountCents)
        #expect(supplied.updatedAt == now)
    }

    @Test("supplying a date is idempotent - a record already watching is left alone")
    func supplyingIsIdempotent() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let pending = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 9, 15)
        )
        #expect(pending.supplyingResumeDate(try day(2026, 12, 1), for: subscription, at: now) == pending)
    }

    @Test("the roll-forward skips a deferred record - it waits on the user, not the calendar")
    func rollForwardSkipsDeferred() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let record = try deferredRecord(subscriptionID: subscription.id)
        let caughtUp = record.catchingUpOnUnansweredChecks(
            for: subscription, asOf: try day(2027, 8, 6), at: now
        )
        #expect(caughtUp == record)
    }

    @Test("a deferred record refuses both verification answers")
    func deferredRefusesAnswers() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let record = try deferredRecord(subscriptionID: subscription.id)
        #expect(record.confirmingChargesStopped(at: now) == record)
        #expect(record.reportingStillCharging(at: now) == record)
        #expect(disputeSummary(for: record, subscription: subscription) == nil)
    }

    @Test("Today surfaces the deferred check as needs action, asking for the date")
    func todaySurfacesDeferredCheck() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let record = try deferredRecord(subscriptionID: subscription.id)
        let today = try day(2026, 8, 6)

        let entry = try #require(todayEntry(for: subscription, cancellation: record, from: today))

        #expect(entry.reason == .verificationNeedsResumeDate)
        #expect(entry.needsAction)
        #expect(entry.date == today)
    }

    @Test("the planner schedules nothing for a deferred check")
    func plannerSkipsDeferred() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        let record = try deferredRecord(subscriptionID: subscription.id)
        let plan = reminderSchedule(
            for: subscription, cancellation: record, from: try day(2026, 8, 6), horizonDays: 90
        )
        #expect(plan.isEmpty)
    }

    @Test("decoding refuses a record whose date and state disagree")
    func decodingEnforcesInvariant() throws {
        let subscription = try makeSubscription(
            status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
        )
        // A pending record whose check date was stripped: undecodable.
        let pending = try makeCancellationRecord(
            subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 9, 15)
        )
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(pending)) as? [String: Any]
        )
        json.removeValue(forKey: "nextChargeDateIfNotCancelled")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CancellationRecord.self, from: stripped)
        }
    }
}
