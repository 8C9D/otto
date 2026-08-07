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
