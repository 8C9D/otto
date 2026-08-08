import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

// Spec §5.0a (v2.2, executed in 6B-Prep-3): one id, one record, one parent.
// The rival-cancellation merge used to give the winner live COPIES of the
// losers' evidence notes while each tombstoned loser kept its own - one note
// id naming records under two parents, which is a name collision in CloudKit,
// the exact subsystem 6B enables. The merge now MOVES the notes; these tests
// prove the stored records reparent rather than duplicate, and that the
// store-wide invariant holds across every table at once.
extension SerializedPersistenceTests {
    @Suite("Evidence-note reparenting (spec §5.0a)")
    struct EvidenceNoteReparentTests {

        @Test(
            "a restore that moves a note between episodes reparents the one stored record",
            arguments: [600, 602]
        )
        func restoreReparentsMovedEvidenceNotes(loserIndex: Int) async throws {
            let (store, containers) = try makeStore()
            let subscription = try makeSubscription(
                index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 1, 15)
            )
            try await store.save(subscription)
            let winner = try makeCancellationEpisode(
                index: 601, subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15)
            )
            var loser = try makeCancellationEpisode(
                index: loserIndex, subscriptionID: subscription.id,
                nextChargeDateIfNotCancelled: try day(2026, 9, 15),
                evidenceNote: "emailed support"
            )
            loser.markedCancelledAt = Date(timeIntervalSince1970: 7_000)
            try await store.save(winner)
            try await store.save(loser)

            // The §4a-2a repair inside the merge MOVES the loser's note to the
            // winner and tombstones the loser holding none; the restore then
            // applies that snapshot over records whose note still sits under
            // the loser. Both parameter orders matter: the loser's id sorts
            // before or after the winner's, so the restore meets the emptied
            // loser first in one order and the note-bearing winner first in
            // the other.
            let current = try await store.completeSnapshot()
            let resolved = try resolveImport(
                current: current, incoming: current, strategy: .merge,
                at: Date(timeIntervalSince1970: 11_000)
            )
            try await store.restore(
                resolved.snapshot, at: Date(timeIntervalSince1970: 11_000), watermarks: .keep
            )

            let noteID = try fixtureUUID(loserIndex + 50)
            let noteRows = try ModelContext(containers.main)
                .fetch(FetchDescriptor<StoredEvidenceNote>())
                .filter { $0.id == noteID }
            #expect(noteRows.count == 1)
            #expect(noteRows.first?.episode?.id == (try fixtureUUID(601)))
            #expect(noteRows.first?.deletedAt == nil)
            #expect(try duplicateLiveIDs(in: containers).isEmpty)
        }
    }
}
