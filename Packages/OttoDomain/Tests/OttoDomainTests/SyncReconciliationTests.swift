import Foundation
import Testing
@testable import OttoDomain

// Spec §5.3 (v2.0): prevention is not reconciliation. These test the pure
// merge rule; the store pass that applies it is tested in OttoPersistence.
@Suite("Ledger duplicate reconciliation (spec §5.3, v2.0)")
struct SyncReconciliationTests {

    private func row(
        _ index: Int,
        createdAt: TimeInterval,
        state: BillingEvent.State = .upcoming,
        userConfirmedAt: Date? = nil,
        acknowledgedAt: Date? = nil,
        actualAmountCents: Int? = nil
    ) throws -> BillingEvent {
        BillingEvent(
            id: try fixtureUUID(index),
            subscriptionID: try fixtureUUID(1),
            expectedDate: try day(2026, 8, 15),
            expectedAmountCents: 1099,
            state: state,
            userConfirmedAt: userConfirmedAt,
            acknowledgedAt: acknowledgedAt,
            actualAmountCents: actualAmountCents,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    @Test("the earliest-created row wins; any acknowledgement and any confirmation count")
    func mergeFoldsStateIn() throws {
        let acknowledged = try row(801, createdAt: 1_000, acknowledgedAt: Date(timeIntervalSince1970: 5_000))
        let confirmed = try row(
            802, createdAt: 2_000, state: .confirmedCharged,
            userConfirmedAt: Date(timeIntervalSince1970: 6_000), actualAmountCents: 1_199
        )

        let merged = try #require(BillingEvent.reconcilingDuplicates([acknowledged, confirmed]))

        #expect(merged.winner.id == acknowledged.id)
        #expect(merged.winner.state == .confirmedCharged)
        #expect(merged.winner.userConfirmedAt == Date(timeIntervalSince1970: 6_000))
        #expect(merged.winner.actualAmountCents == 1_199)
        #expect(merged.winner.acknowledgedAt == Date(timeIntervalSince1970: 5_000))
        #expect(merged.loserIDs == [confirmed.id])

        // The same records in the other order - the other device's arrival
        // sequence - produce the identical decision.
        let mirrored = try #require(BillingEvent.reconcilingDuplicates([confirmed, acknowledged]))
        #expect(mirrored == merged)
    }

    @Test("a winner that is already confirmed keeps its own answer")
    func confirmedWinnerKeepsAnswer() throws {
        let winner = try row(
            801, createdAt: 1_000, state: .confirmedNotCharged,
            userConfirmedAt: Date(timeIntervalSince1970: 5_000)
        )
        let rival = try row(
            802, createdAt: 2_000, state: .confirmedCharged,
            userConfirmedAt: Date(timeIntervalSince1970: 6_000)
        )

        let merged = try #require(BillingEvent.reconcilingDuplicates([winner, rival]))

        // The user confirmed THIS row; a twin's answer does not overwrite it.
        #expect(merged.winner.state == .confirmedNotCharged)
        #expect(merged.winner.userConfirmedAt == Date(timeIntervalSince1970: 5_000))
    }

    @Test("a single row is not a duplicate - nothing to reconcile")
    func singleRowIsLeftAlone() throws {
        #expect(BillingEvent.reconcilingDuplicates([try row(801, createdAt: 1_000)]) == nil)
    }
}

// Spec §4a principle 2a (v2.1): one shape for every convergence rule - the
// earliest record survives, the losers' child records and state merge into it,
// the losers are tombstoned by the applying paths.
@Suite("Rival cancellation reconciliation (spec §4a principle 2a, v2.1)")
struct CancellationRivalReconciliationTests {

    private func episode(
        _ index: Int,
        markedCancelledAt: TimeInterval,
        state: CancellationEpisode.VerificationState = .pending,
        unansweredCheckCount: Int = 0,
        expectedChargeAmountCents: Int? = nil,
        statusAtStart: SubscriptionStatus? = nil,
        note: String? = nil
    ) throws -> CancellationEpisode {
        CancellationEpisode(
            id: try fixtureUUID(index),
            subscriptionID: try fixtureUUID(1),
            markedCancelledAt: Date(timeIntervalSince1970: markedCancelledAt),
            statusAtStart: statusAtStart,
            nextChargeDateIfNotCancelled: try day(2026, 9, 1),
            expectedChargeAmountCents: expectedChargeAmountCents,
            verificationState: state,
            unansweredCheckCount: unansweredCheckCount,
            evidenceNotes: try note.map {
                [EvidenceNote(
                    id: try fixtureUUID(index + 50), text: $0,
                    createdAt: Date(timeIntervalSince1970: markedCancelledAt),
                    updatedAt: Date(timeIntervalSince1970: markedCancelledAt)
                )]
            } ?? [],
            createdAt: Date(timeIntervalSince1970: markedCancelledAt),
            updatedAt: Date(timeIntervalSince1970: markedCancelledAt)
        )
    }

    @Test("the earliest cancellation wins and wears the losers' notes and progress - from both arrival orders")
    func earliestWinsAndMerges() throws {
        // The user cancelled once; both devices recorded it. The later record
        // carries the evidence and already observed a charge arriving.
        let earliest = try episode(601, markedCancelledAt: 1_000)
        let later = try episode(
            602, markedCancelledAt: 2_000, state: .stillCharging,
            unansweredCheckCount: 2, expectedChargeAmountCents: 1_099,
            statusAtStart: .active, note: "confirmation #123"
        )

        let merged = try #require(CancellationEpisode.reconcilingOpenRivals(among: [earliest, later]))

        #expect(merged.winner.id == earliest.id)
        #expect(merged.loserIDs == [later.id])
        #expect(merged.winner.liveEvidenceNotes.map(\.text) == ["confirmation #123"])
        // The loser's observation survives; un-observing a charge would be loss.
        #expect(merged.winner.verificationState == .stillCharging)
        #expect(merged.winner.unansweredCheckCount == 2)
        // The nil-means-legacy fields heal from the twin that recorded them.
        #expect(merged.winner.expectedChargeAmountCents == 1_099)
        #expect(merged.winner.statusAtStart == .active)
        // The winner keeps its own earlier check date - watching sooner,
        // never too late.
        #expect(merged.winner.nextChargeDateIfNotCancelled == (try day(2026, 9, 1)))

        let mirrored = try #require(CancellationEpisode.reconcilingOpenRivals(among: [later, earliest]))
        #expect(mirrored == merged)
    }

    @Test("a winner past .pending keeps its own observation")
    func progressedWinnerKeepsState() throws {
        let earliest = try episode(601, markedCancelledAt: 1_000, state: .needsManualReview)
        let later = try episode(602, markedCancelledAt: 2_000, state: .stillCharging)

        let merged = try #require(CancellationEpisode.reconcilingOpenRivals(among: [earliest, later]))

        #expect(merged.winner.verificationState == .needsManualReview)
    }

    @Test("an .awaitingResumeDate winner takes no state graft - it has no check date to watch with")
    func awaitingResumeDateWinnerHolds() throws {
        var earliest = try episode(601, markedCancelledAt: 1_000)
        earliest.verificationState = .awaitingResumeDate
        earliest.nextChargeDateIfNotCancelled = nil
        let later = try episode(602, markedCancelledAt: 2_000, state: .stillCharging)

        let merged = try #require(CancellationEpisode.reconcilingOpenRivals(among: [earliest, later]))

        #expect(merged.winner.verificationState == .awaitingResumeDate)
        #expect(merged.winner.nextChargeDateIfNotCancelled == nil)
    }

    @Test("a single open episode is not a rivalry - nothing to reconcile")
    func singleEpisodeIsLeftAlone() throws {
        #expect(CancellationEpisode.reconcilingOpenRivals(among: [try episode(601, markedCancelledAt: 1_000)]) == nil)
    }
}
