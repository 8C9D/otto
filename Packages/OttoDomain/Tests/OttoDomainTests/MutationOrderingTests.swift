import Foundation
import Testing
@testable import OttoDomain

// The bug class that actually shipped (Wave 4, spec §5.2a v1.5): an operation
// that both mutates status and derives from status must derive FIRST, because
// `billingAnchor(asOf:)` keys off the stored status and answers differently
// once a cancellation overwrites it. Pure functions cannot prevent the ordering
// mistake - the read and the write are each individually correct - so these
// tests pin the property the fix relies on instead: the derivations the flows
// persist must be computed from data the mutation cannot destroy, and therefore
// must answer identically before and after the overwrite.

@Suite("Derive before you mutate (spec §5.2a, v1.5)")
struct MutationOrderingTests {

    /// The exact state the Wave 4 bug shipped in: a trial converted Jul 31,
    /// never flipped, cancelled Aug 5.
    private func convertedUnflippedTrial() throws -> (Subscription, TrialTerm) {
        let trial = try makeTrialTerm(
            startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599
        )
        let subscription = try makeSubscription(
            status: .trial, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        return (subscription, trial)
    }

    @Test(
        "the cancellation derivations are immune to the status overwrite that precedes them",
        arguments: [SubscriptionStatus.cancellationPending, .cancelled]
    )
    func cancellationDerivationsSurviveOverwrite(overwritten: SubscriptionStatus) throws {
        let (before, _) = try convertedUnflippedTrial()
        var after = before
        after.status = overwritten
        let today = try day(2026, 8, 5)

        // The check date: Aug 31 from the conversion anchor - and the same
        // answer whether or not the status flip already happened, because the
        // derivation reads the trial term the overwrite cannot destroy.
        let beforeDate = verificationCheckDate(for: before, asOf: today)
        let afterDate = verificationCheckDate(for: after, asOf: today)
        #expect(beforeDate == afterDate)
        #expect(afterDate == (try day(2026, 8, 31)))

        // The check amount (v1.5): same property, same reason.
        #expect(wouldBeChargeAmountCents(on: afterDate, for: before)
            == wouldBeChargeAmountCents(on: afterDate, for: after))
        #expect(wouldBeChargeAmountCents(on: afterDate, for: after) == 1599)
    }

    @Test("billingAnchor is NOT overwrite-immune - which is why flows must derive before mutating")
    func billingAnchorIsStatusKeyed() throws {
        // Documents the sharp edge instead of hiding it: billingAnchor keys off
        // the stored .trial status, so the Wave 4 bug - mutate, then derive
        // through it - watched Sep 1 instead of Aug 31. Any future flow tempted
        // to call it after a status write has this failure to explain first.
        let (before, trial) = try convertedUnflippedTrial()
        var after = before
        after.status = .cancellationPending
        let today = try day(2026, 8, 5)

        #expect(before.billingAnchor(asOf: today) == trial.conversionDate)
        #expect(after.billingAnchor(asOf: today) == before.cycleStartDay)
        #expect(before.billingAnchor(asOf: today) != after.billingAnchor(asOf: today))
    }
}
