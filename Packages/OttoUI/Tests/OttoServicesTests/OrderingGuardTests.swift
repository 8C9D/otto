import Foundation
import OttoDomain
import Testing
@testable import OttoServices

// The standing guard for the Wave 4 bug class (spec §5.2a, v1.5): every flow
// operation that both MUTATES state and DERIVES values from it is tested here
// by snapshotting the world before the flow runs, recomputing each
// derived-persisted value from the snapshot, and requiring equality. A flow
// that derives after mutating produces a mismatch against the snapshot - the
// failure Wave 4 shipped, caught structurally instead of by scenario luck.
//
// A NEW flow operation that mutates and derives gets a test in this file as
// part of landing it.

@Suite("Flow ordering: derived values match the pre-mutation snapshot (spec §5.2a, v1.5)")
struct OrderingGuardTests {

    private struct Scenario {
        let label: String
        let subscription: Subscription
        let today: CalendarDay
    }

    /// Three shapes, including the one the Wave 4 bug shipped in (the
    /// converted-unflipped trial, where deriving after the status flip gives a
    /// different - wrong - date).
    private func cancellationScenarios() throws -> [Scenario] {
        let convertedTrial = try makeTrialTerm(
            index: 500, startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599
        )
        let unconvertedTrial = try makeTrialTerm(
            index: 501, startDate: try day(2026, 8, 1), lengthDays: 14, convertsToAmountCents: 1899
        )
        return [
            Scenario(
                label: "plain active",
                subscription: try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15)),
                today: try day(2026, 8, 6)
            ),
            Scenario(
                label: "unconverted trial",
                subscription: try makeSubscription(
                    index: 2, status: .trial, cycleStartDay: try day(2026, 8, 1),
                    trial: unconvertedTrial
                ),
                today: try day(2026, 8, 6)
            ),
            Scenario(
                label: "converted-unflipped trial",
                subscription: try makeSubscription(
                    index: 3, status: .trial, cycleStartDay: try day(2026, 7, 1),
                    trial: convertedTrial
                ),
                today: try day(2026, 8, 5)
            )
        ]
    }

    @Test("startCancellation persists exactly what the pre-mutation subscription derives")
    func startCancellationDerivesFirst() async throws {
        for scenario in try cancellationScenarios() {
            let (label, snapshot, today) = (scenario.label, scenario.subscription, scenario.today)
            let fixture = SchedulerFixture()
            await fixture.subscriptions.seed([snapshot])

            let start = try await fixture.flows.startCancellation(
                subscriptionID: snapshot.id, now: try fixtureNow(), today: today
            )

            // The mutation happened...
            let mutated = try await fixture.subscriptions.subscription(withID: snapshot.id)
            #expect(mutated?.storedStatus == .cancellationPending, "\(label)")

            // ...and every derived-persisted value equals a fresh derivation
            // from the PRE-mutation snapshot.
            let record = try #require(start?.record, "\(label)")
            let expectedDate = try #require(verificationCheckDate(for: snapshot, asOf: today), "\(label)")
            #expect(record.nextChargeDateIfNotCancelled == expectedDate, "\(label)")
            #expect(
                record.expectedChargeAmountCents
                    == wouldBeChargeAmountCents(on: expectedDate, for: snapshot),
                "\(label)"
            )
        }
    }

    @Test("confirmTrialConversion persists exactly the pre-mutation snapshot's own derivation")
    func confirmConversionDerivesFirst() async throws {
        let trial = try makeTrialTerm(
            startDate: try day(2026, 7, 1), lengthDays: 30, convertsToAmountCents: 1599
        )
        let snapshot = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 7, 1), trial: trial
        )
        let fixture = SchedulerFixture()
        await fixture.subscriptions.seed([snapshot])
        let today = try day(2026, 8, 5)
        let now = try fixtureNow()

        try await fixture.flows.confirmTrialConversion(
            subscriptionID: snapshot.id, now: now, today: today
        )

        // The flipped subscription is the PURE derivation from the snapshot -
        // conversion anchor, converted amount, retained term - nothing computed
        // from post-mutation state.
        let persisted = try await fixture.subscriptions.subscription(withID: snapshot.id)
        #expect(persisted == snapshot.confirmingConversion(asOf: today, at: now))
    }

    @Test("answerVerification's dispute row derives from the record and snapshot, not post-flip state")
    func answerVerificationDerivesFromRecord() async throws {
        // Here the mutated state is the RECORD (pending -> stillCharging); the
        // row's amount must come from what was stored at cancellation - or, for
        // a pre-v1.5 record like this one, from the snapshot's derivation.
        let snapshot = try makeSubscription(index: 1, cycleStartDay: try day(2026, 1, 15))
        let fixture = SchedulerFixture()
        await fixture.subscriptions.seed([snapshot])
        let checkDate = try day(2026, 8, 15)
        await fixture.cancellations.seed([CancellationEpisode(
            id: try fixtureUUID(600),
            subscriptionID: snapshot.id,
            markedCancelledAt: Date(timeIntervalSince1970: 4_000),
            nextChargeDateIfNotCancelled: checkDate,
            verificationState: .pending,
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )])

        let summary = try #require(try await fixture.flows.answerVerification(
            subscriptionID: snapshot.id, chargesStopped: false,
            now: try fixtureNow(), today: checkDate
        ))

        let expectedAmount = wouldBeChargeAmountCents(on: checkDate, for: snapshot)
        #expect(summary.chargeAmountCents == expectedAmount)
        let row = try await fixture.billingEvents.events(forSubscription: snapshot.id)
            .first { $0.state == .unexpectedCharge }
        #expect(row?.expectedDate == checkDate)
        #expect(row?.expectedAmountCents == expectedAmount)
    }
}
