import Foundation
import Testing
@testable import OttoDomain

// ⛔ Wall-clock stamps are a merge input and the device clock is not monotonic
// (docs/sync-safety.md, found Aug 2026 in REAL exported data): the "Gate Test"
// subscription's cancellation episode and billing event were written under the
// advanced clock of verification procedure 1 and tombstoned after the clock was
// restored, so their `deletedAt` precedes their `createdAt`. The import repairs
// both sides before any rule compares them, and counts what it repaired -
// merging on a stamp nobody checked is how the wrong twin donates a money field.
@Suite("Import repairs the stamps it merges on (docs/sync-safety.md)")
struct ImportStampRepairTests {

    /// The incident's own instants, so the test documents it.
    private let gateTestCreated = Date(timeIntervalSince1970: 1_786_371_065)  // 2026-08-10T14:11:05Z
    private let clockRestored = Date(timeIntervalSince1970: 1_786_210_329)  // 2026-08-08T17:32:09Z
    private let importInstant = Date(timeIntervalSince1970: 1_786_838_400)  // 2026-08-16T00:00:00Z

    private func gateTest() throws -> Subscription {
        var subscription = try makeSubscription(index: 1, status: .cancellationPending, cycleStartDay: try day(2026, 8, 1))
        subscription.name = "Gate Test"
        return subscription
    }

    @Test("⛔ the field case: a tombstone stamped BEFORE its own record's creation is raised to it")
    func deletedBeforeCreatedIsRepaired() throws {
        let subscription = try gateTest()
        var episode = try makeCancellationEpisode(
            index: 601, subscriptionID: subscription.id, nextChargeDateIfNotCancelled: try day(2026, 9, 10)
        )
        episode.createdAt = gateTestCreated
        episode.updatedAt = gateTestCreated
        episode.deletedAt = clockRestored
        let incoming = OttoDataSnapshot(subscriptions: [subscription], cancellationEpisodes: [episode])

        let resolved = try resolveImport(
            current: OttoDataSnapshot(), incoming: incoming, strategy: .merge, at: importInstant
        )

        let stored = try #require(resolved.snapshot.cancellationEpisodes.first)
        // Raised to `createdAt`, never the other way round: `createdAt` is the
        // stamp the ledger merge orders on, and moving it would rewrite which
        // twin counts as the original.
        #expect(stored.deletedAt == gateTestCreated)
        #expect(stored.createdAt == gateTestCreated)
        #expect(resolved.summary.timestampOrderRepairs == 1)
        #expect(resolved.summary.futureStampClamps == 0)
    }

    @Test("⛔ a future stamp is not sticky: it is clamped to the import instant, and the next honest edit wins")
    func futureStampLosesToTheNextEdit() throws {
        let local = try makeSubscription(index: 1, status: .active, cycleStartDay: try day(2026, 8, 1))
        var fromTheFile = local
        fromTheFile.name = "written under an advanced clock"
        // Two days ahead of the import: under plain last-write-wins this copy
        // would beat every honest edit until real time caught up.
        fromTheFile.updatedAt = importInstant.addingTimeInterval(2 * 24 * 60 * 60)
        let file = OttoDataSnapshot(subscriptions: [fromTheFile])

        let first = try resolveImport(
            current: OttoDataSnapshot(subscriptions: [local]), incoming: file,
            strategy: .merge, at: importInstant
        )

        let imported = try #require(first.snapshot.subscriptions.first)
        #expect(imported.name == "written under an advanced clock")
        #expect(imported.updatedAt == importInstant)
        #expect(first.summary.futureStampClamps == 1)

        // One second later the user edits the record here. Re-importing the same
        // file must not undo that edit - which is exactly what the unclamped
        // future stamp did.
        let editedAt = importInstant.addingTimeInterval(1)
        var edited = imported
        edited.name = "edited on this device"
        edited.updatedAt = monotonicStamp(editedAt, notBefore: edited.updatedAt)

        let second = try resolveImport(
            current: OttoDataSnapshot(subscriptions: [edited]), incoming: file,
            strategy: .merge, at: editedAt
        )

        #expect(second.snapshot.subscriptions.first?.name == "edited on this device")
        #expect(second.summary.subscriptions.skippedOlder == 1)
    }

    @Test("a replace repairs the file's stamps too - the strategy does not decide what a stamp means")
    func replaceRepairsTheFile() throws {
        let subscription = try gateTest()
        var event = BillingEvent(
            id: try fixtureUUID(102), subscriptionID: subscription.id,
            expectedDate: try day(2026, 8, 10), expectedAmountCents: 1099, state: .upcoming,
            createdAt: Date(timeIntervalSince1970: 1_786_371_452),  // 2026-08-10T14:17:32Z
            updatedAt: Date(timeIntervalSince1970: 1_786_371_452),
            deletedAt: clockRestored
        )
        event.updatedAt = importInstant.addingTimeInterval(60)
        let incoming = OttoDataSnapshot(subscriptions: [subscription], billingEvents: [event])

        let resolved = try resolveImport(
            current: OttoDataSnapshot(), incoming: incoming, strategy: .replace, at: importInstant
        )

        let stored = try #require(resolved.snapshot.billingEvents.first)
        #expect(stored.deletedAt == stored.createdAt)
        #expect(stored.updatedAt == importInstant)
        #expect(resolved.summary.timestampOrderRepairs == 1)
        #expect(resolved.summary.futureStampClamps == 1)
    }

    @Test("an embedded child's stamps are repaired with its parent's")
    func embeddedChildrenAreRepaired() throws {
        var episode = try makePauseEpisode(index: 701, startedOn: try day(2026, 8, 1))
        episode.createdAt = gateTestCreated
        episode.updatedAt = clockRestored
        let subscription = try makeSubscription(
            index: 1, status: .paused, cycleStartDay: try day(2026, 8, 1), pauseEpisodes: [episode]
        )

        let resolved = try resolveImport(
            current: OttoDataSnapshot(), incoming: OttoDataSnapshot(subscriptions: [subscription]),
            strategy: .merge, at: importInstant
        )

        let stored = try #require(resolved.snapshot.subscriptions.first?.pauseEpisodes.first)
        #expect(stored.updatedAt == gateTestCreated)
        #expect(resolved.summary.timestampOrderRepairs == 1)
    }
}
