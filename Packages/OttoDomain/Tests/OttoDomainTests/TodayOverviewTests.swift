import Foundation
import Testing
import OttoDomain

@Suite("Today overview classification (spec §7.1)")
struct TodayOverviewTests {

    private let today = CalendarDay(year: 2026, month: 8, day: 6)

    private func overview(
        _ subscriptions: [Subscription],
        cancellations: [UUID: CancellationRecord] = [:]
    ) throws -> TodayOverview {
        let today = try #require(today)
        return todayOverview(subscriptions: subscriptions, cancellations: cancellations, from: today)
    }

    @Test("an active subscription lands in Next 30 days or Later by its next charge date")
    func activeSplitsAtThirtyDays() throws {
        // Charges Aug 15 (inside 30 days) and Oct 1 (beyond Sep 5).
        let soon = try makeSubscription(index: 1, status: .active, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        let later = try makeSubscription(index: 2, status: .active, cycle: .annual, cycleStartDay: try day(2025, 10, 1))

        let overview = try overview([soon, later])

        #expect(overview.needsAction.isEmpty)
        #expect(overview.next30Days.map(\.id) == [soon.id])
        #expect(overview.next30Days.first?.date == (try day(2026, 8, 15)))
        #expect(overview.next30Days.first?.reason == .upcomingCharge(amountCents: soon.amountCents))
        #expect(overview.later.map(\.id) == [later.id])
        #expect(overview.later.first?.date == (try day(2026, 10, 1)))
    }

    @Test("a charge landing today is in Next 30 days, not lost")
    func chargeToday() throws {
        let sub = try makeSubscription(index: 1, status: .active, cycle: .monthly, cycleStartDay: try day(2026, 8, 6))
        let overview = try overview([sub])
        #expect(overview.next30Days.first?.date == today)
    }

    @Test("a trial inside its cancel-by window needs action, keyed on the cancel-by date")
    func trialInsideWindow() throws {
        // Cancel by Aug 9, lead 3: the window opened Aug 6 - today.
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 28), lengthDays: 14)
        let sub = try makeSubscription(
            index: 1, status: .trial, cycle: .monthly, cycleStartDay: try day(2026, 7, 28), trial: trial
        )

        let overview = try overview([sub])

        #expect(overview.needsAction.map(\.reason) == [.trialActionNeeded])
        #expect(overview.needsAction.first?.date == trial.cancelByDate)
    }

    @Test("a trial ahead of its window is an upcoming conversion at the converted amount")
    func trialAheadOfWindow() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1), lengthDays: 30)
        let sub = try makeSubscription(
            index: 1, status: .trial, cycle: .monthly, cycleStartDay: try day(2026, 8, 1), trial: trial
        )

        let overview = try overview([sub])

        #expect(overview.needsAction.isEmpty)
        #expect(overview.next30Days.map(\.reason) == [.trialConverts(amountCents: trial.convertsToAmountCents)])
        #expect(overview.next30Days.first?.date == trial.conversionDate)
    }

    @Test("a trial whose conversion has passed unresolved still needs action - it never vanishes")
    func trialPastConversion() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1), lengthDays: 14)
        let sub = try makeSubscription(
            index: 1, status: .trial, cycle: .monthly, cycleStartDay: try day(2026, 7, 1), trial: trial
        )

        let overview = try overview([sub])

        #expect(overview.needsAction.map(\.reason) == [.trialActionNeeded])
    }

    @Test("a paused subscription surfaces only its resume date")
    func paused() throws {
        let resuming = try makeSubscription(
            index: 1, status: .paused, cycle: .monthly, cycleStartDay: try day(2026, 1, 15),
            pauseEndsOn: try day(2026, 8, 20)
        )
        let indefinite = try makeSubscription(
            index: 2, status: .paused, cycle: .monthly, cycleStartDay: try day(2026, 1, 15)
        )

        let overview = try overview([resuming, indefinite])

        #expect(overview.next30Days.map(\.id) == [resuming.id])
        #expect(overview.next30Days.map(\.reason) == [.pauseResumes])
        #expect(overview.later.isEmpty)
        #expect(overview.needsAction.isEmpty)
    }

    @Test("a pending verification whose check date arrived needs action; a future one is upcoming")
    func pendingVerifications() throws {
        let due = try makeSubscription(index: 1, status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let ahead = try makeSubscription(
            index: 2, status: .cancellationPending, cycle: .monthly, cycleStartDay: try day(2026, 5, 25)
        )
        let cancellations = [
            due.id: try makeCancellationRecord(
                index: 601, subscriptionID: due.id, nextChargeDateIfNotCancelled: try day(2026, 7, 20)
            ),
            ahead.id: try makeCancellationRecord(
                index: 602, subscriptionID: ahead.id, nextChargeDateIfNotCancelled: try day(2026, 8, 25)
            )
        ]

        let overview = try overview([due, ahead], cancellations: cancellations)

        #expect(overview.needsAction.map(\.id) == [due.id])
        #expect(overview.needsAction.map(\.reason) == [.verificationDue])
        #expect(overview.needsAction.first?.date == (try day(2026, 7, 20)))
        #expect(overview.next30Days.map(\.id) == [ahead.id])
        #expect(overview.next30Days.map(\.reason) == [.verificationCheck])
    }

    @Test("a failed verification needs action; a verified one shows nothing")
    func resolvedVerifications() throws {
        let failed = try makeSubscription(index: 1, status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let stopped = try makeSubscription(index: 2, status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 25))
        let cancellations = [
            failed.id: try makeCancellationRecord(
                index: 601, subscriptionID: failed.id,
                nextChargeDateIfNotCancelled: try day(2026, 7, 20), verificationState: .stillCharging
            ),
            stopped.id: try makeCancellationRecord(
                index: 602, subscriptionID: stopped.id,
                nextChargeDateIfNotCancelled: try day(2026, 7, 25), verificationState: .verifiedStopped
            )
        ]

        let overview = try overview([failed, stopped], cancellations: cancellations)

        #expect(overview.needsAction.map(\.id) == [failed.id])
        #expect(overview.needsAction.map(\.reason) == [.verificationFailed])
        #expect(overview.next30Days.isEmpty)
        #expect(overview.later.isEmpty)
    }

    @Test("a cancelled subscription with no record surfaces as due today, never silently unwatched")
    func cancelledWithoutRecord() throws {
        let sub = try makeSubscription(index: 1, status: .cancelled, cycle: .monthly, cycleStartDay: try day(2026, 5, 20))
        let overview = try overview([sub])
        #expect(overview.needsAction.map(\.reason) == [.verificationDue])
        #expect(overview.needsAction.first?.date == today)
    }

    @Test("archived and soft-deleted subscriptions appear nowhere")
    func archivedAndDeleted() throws {
        let archived = try makeSubscription(index: 1, status: .archived, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        var deleted = try makeSubscription(index: 2, status: .active, cycle: .monthly, cycleStartDay: try day(2026, 1, 15))
        deleted.deletedAt = Date(timeIntervalSince1970: 9_000)

        let overview = try overview([archived, deleted])

        #expect(overview.needsAction.isEmpty)
        #expect(overview.next30Days.isEmpty)
        #expect(overview.later.isEmpty)
    }

    @Test("sections sort by date, then name, deterministically")
    func sorting() throws {
        let bLater = try makeSubscription(index: 1, status: .active, cycle: .monthly, cycleStartDay: try day(2026, 1, 20))
        let aSooner = try makeSubscription(index: 2, status: .active, cycle: .monthly, cycleStartDay: try day(2026, 1, 10))

        let overview = try overview([bLater, aSooner])

        #expect(overview.next30Days.map(\.date) == [try day(2026, 8, 10), try day(2026, 8, 20)])
    }
}
