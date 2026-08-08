import Foundation
import Testing
@testable import OttoDomain

// MARK: - Import resolution

@Suite("Import conflict policy (Wave 8: explicit, never silent)")
struct ImportResolutionTests {

    private let older = Date(timeIntervalSinceReferenceDate: 100)
    private let newer = Date(timeIntervalSinceReferenceDate: 200)
    private let importInstant = Date(timeIntervalSinceReferenceDate: 900)

    private func subscription(_ index: Int, updatedAt: Date, name: String = "Sub") throws -> Subscription {
        Subscription(
            id: try fixtureUUID(index),
            name: name,
            category: .other,
            status: .active,
            amountCents: 1099,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            createdAt: older,
            updatedAt: updatedAt
        )
    }

    @Test("merge keeps both sides, adds file-only records, and lets the newer copy win")
    func mergeLastWriteWins() throws {
        let current = OttoDataSnapshot(subscriptions: [
            try subscription(1, updatedAt: newer, name: "kept - local newer"),
            try subscription(2, updatedAt: older, name: "will be updated"),
            try subscription(3, updatedAt: older, name: "local only")
        ])
        let incoming = OttoDataSnapshot(subscriptions: [
            try subscription(1, updatedAt: older, name: "older import copy"),
            try subscription(2, updatedAt: newer, name: "newer import copy"),
            try subscription(4, updatedAt: older, name: "file only")
        ])

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge, at: importInstant)

        let byID = Dictionary(uniqueKeysWithValues: resolved.snapshot.subscriptions.map { ($0.id, $0) })
        #expect(byID.count == 4)
        #expect(byID[try fixtureUUID(1)]?.name == "kept - local newer")
        #expect(byID[try fixtureUUID(2)]?.name == "newer import copy")
        #expect(byID[try fixtureUUID(3)]?.name == "local only")
        #expect(byID[try fixtureUUID(4)]?.name == "file only")
        #expect(resolved.summary.subscriptions == ImportCounts(added: 1, updated: 1, skippedOlder: 1))
    }

    @Test("importing your own fresh export back is a no-op merge")
    func selfImportIsNoOp() throws {
        let current = try fullSnapshot()
        let data = try exportData(from: current, exportedAt: Date(timeIntervalSinceReferenceDate: 0))

        let resolved = try resolveImport(
            current: current, incoming: try importedSnapshot(from: data), strategy: .merge, at: importInstant
        )

        #expect(resolved.snapshot == current)
        #expect(resolved.summary.subscriptions.added == 0)
        #expect(resolved.summary.subscriptions.updated == 0)
    }

    @Test("replace becomes exactly the file, and counts what it removed")
    func replaceIsExact() throws {
        let current = OttoDataSnapshot(subscriptions: [
            try subscription(1, updatedAt: older),
            try subscription(2, updatedAt: older)
        ])
        let incoming = OttoDataSnapshot(subscriptions: [try subscription(3, updatedAt: newer)])

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .replace, at: importInstant)

        #expect(resolved.snapshot == incoming)
        #expect(resolved.summary.subscriptions == ImportCounts(added: 1, removed: 2))
    }

    @Test("two open cancellations for one subscription merge: the earliest stays, wearing the loser's notes")
    func singleOpenCancellation() throws {
        // Each side cancelled independently, so the merge unites two OPEN
        // episodes - two recordings of one real-world act. §4a principle 2a
        // (v2.1): the EARLIEST stays the current watch (the earliest is when
        // the user actually acted, and its earlier check date errs toward
        // watching sooner), the loser's evidence merges in, and the loser is
        // tombstoned - counted, never silent.
        let sub = try subscription(1, updatedAt: older)
        func episode(
            _ index: Int, markedCancelledAt: Date, note: String? = nil
        ) throws -> CancellationEpisode {
            CancellationEpisode(
                id: try fixtureUUID(index),
                subscriptionID: sub.id,
                markedCancelledAt: markedCancelledAt,
                nextChargeDateIfNotCancelled: try day(2026, 9, 1),
                verificationState: .pending,
                evidenceNotes: try note.map {
                    [EvidenceNote(id: try fixtureUUID(index + 50), text: $0, createdAt: newer, updatedAt: newer)]
                } ?? [],
                createdAt: older,
                updatedAt: markedCancelledAt
            )
        }
        let current = OttoDataSnapshot(
            subscriptions: [sub], cancellationEpisodes: [try episode(601, markedCancelledAt: older)]
        )
        let incoming = OttoDataSnapshot(
            subscriptions: [sub],
            cancellationEpisodes: [try episode(602, markedCancelledAt: newer, note: "confirmation #123")]
        )

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge, at: importInstant)

        #expect(resolved.snapshot.cancellationEpisodes.count == 2)
        let open = resolved.snapshot.cancellationEpisodes.filter { $0.isOpen && $0.deletedAt == nil }
        #expect(open.map(\.id) == [try fixtureUUID(601)])
        // The loser's note now lives on the surviving watch.
        #expect(open.first?.liveEvidenceNotes.map(\.text) == ["confirmation #123"])
        let tombstoned = try #require(
            resolved.snapshot.cancellationEpisodes.first { $0.id == (try fixtureUUID(602)) }
        )
        #expect(tombstoned.deletedAt == importInstant)
        #expect(tombstoned.updatedAt == importInstant)
        // Moved, not copied (spec §5.0a): the loser is tombstoned holding
        // none, so one note id never names records under two parents.
        #expect(tombstoned.evidenceNotes.isEmpty)
        // Added (the incoming episode arrived live), updated (the merged
        // winner), and removed (the loser stopped being visible when it was
        // tombstoned - a live-record transition, counted as what the user
        // sees; Wave 10, defect H).
        #expect(resolved.summary.cancellationEpisodes.added == 1)
        #expect(resolved.summary.cancellationEpisodes.updated == 1)
        #expect(resolved.summary.cancellationEpisodes.removed == 1)

        // The other device resolves the mirrored import - ITS copy is current,
        // the other side's arrives - and reaches the same live state.
        let mirrored = try resolveImport(current: incoming, incoming: current, strategy: .merge, at: importInstant)
        let mirroredOpen = mirrored.snapshot.cancellationEpisodes.filter { $0.isOpen && $0.deletedAt == nil }
        #expect(mirroredOpen == open)
    }

    @Test("a merge that produces two live default cards keeps the newest default")
    func singleDefaultCard() throws {
        func card(_ index: Int, updatedAt: Date) throws -> PaymentMethod {
            PaymentMethod(
                id: try fixtureUUID(index), label: "Card \(index)", last4: "000\(index)",
                issuer: "Bank", expiryMonth: 1, expiryYear: 2030, isDefault: true,
                createdAt: older, updatedAt: updatedAt
            )
        }
        let current = OttoDataSnapshot(paymentMethods: [try card(1, updatedAt: older)])
        let incoming = OttoDataSnapshot(paymentMethods: [try card(2, updatedAt: newer)])

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge, at: importInstant)

        let defaults = resolved.snapshot.paymentMethods.filter(\.isDefault)
        #expect(defaults.map(\.id) == [try fixtureUUID(2)])
    }

    @Test("a child row naming a subscription nobody has is refused before anything applies")
    func danglingReferenceRefused() throws {
        let incoming = OttoDataSnapshot(billingEvents: [
            BillingEvent(
                id: try fixtureUUID(100), subscriptionID: try fixtureUUID(999),
                expectedDate: try day(2026, 1, 1), expectedAmountCents: 1099, state: .upcoming,
                createdAt: older, updatedAt: older
            )
        ])

        #expect(throws: ExportFormatError.self) {
            try resolveImport(current: OttoDataSnapshot(), incoming: incoming, strategy: .replace, at: importInstant)
        }
    }
}

// Wave 10, defect H: the summary counts LIVE records. The field run restored a
// backup and read "Subscriptions: 4 added, 7 charges added" while three
// subscriptions existed anywhere in the app - the export's fourth carried
// `deletedAt`, plus four tombstoned charge rows. The data was correct
// (per-record sync needs tombstones, §4a); the count vouched for records the
// user cannot see, in the one summary whose job is saying a restore worked.
@Suite("Import counts describe live records (Wave 10, defect H)")
struct ImportTombstoneCountTests {

    private let older = Date(timeIntervalSinceReferenceDate: 100)
    private let newer = Date(timeIntervalSinceReferenceDate: 200)
    private let importInstant = Date(timeIntervalSinceReferenceDate: 900)

    private func subscription(
        _ index: Int, updatedAt: Date, deletedAt: Date? = nil
    ) throws -> Subscription {
        Subscription(
            id: try fixtureUUID(index),
            name: "Sub \(index)",
            category: .other,
            status: .active,
            amountCents: 1099,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            createdAt: older,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func event(
        _ index: Int, subscription subIndex: Int, deletedAt: Date? = nil
    ) throws -> BillingEvent {
        BillingEvent(
            id: try fixtureUUID(100 + index), subscriptionID: try fixtureUUID(subIndex),
            expectedDate: try day(2026, 1, 15).adding(days: index), expectedAmountCents: 1099,
            state: .upcoming, createdAt: older, updatedAt: older, deletedAt: deletedAt
        )
    }

    @Test("⛔ the field case: a fresh-install restore counts 3 subscriptions and 7 charges, not the tombstones")
    func restoreCountsLiveRecordsOnly() throws {
        // The export: four subscriptions, one tombstoned; eleven charge rows,
        // four tombstoned. Restored onto a fresh install (empty database).
        let incoming = OttoDataSnapshot(
            subscriptions: [
                try subscription(1, updatedAt: older),
                try subscription(2, updatedAt: older),
                try subscription(3, updatedAt: older),
                try subscription(4, updatedAt: older, deletedAt: older)
            ],
            billingEvents: try (0..<11).map { index in
                try event(index, subscription: 1 + index % 3, deletedAt: index < 4 ? older : nil)
            }
        )

        let resolved = try resolveImport(
            current: OttoDataSnapshot(), incoming: incoming, strategy: .replace, at: importInstant
        )

        // Everything lands in the database - tombstones are sync bookkeeping
        // and must survive the trip - but the summary states what the user
        // actually recovered.
        #expect(resolved.snapshot.subscriptions.count == 4)
        #expect(resolved.snapshot.billingEvents.count == 11)
        #expect(resolved.summary.subscriptions == ImportCounts(added: 3))
        #expect(resolved.summary.billingEvents == ImportCounts(added: 7))
    }

    @Test("replace: a live record the file carries only as a tombstone counts as removed")
    func replaceCountsTombstonedLocalAsRemoved() throws {
        let current = OttoDataSnapshot(subscriptions: [try subscription(1, updatedAt: older)])
        let incoming = OttoDataSnapshot(
            subscriptions: [try subscription(1, updatedAt: newer, deletedAt: newer)]
        )

        let resolved = try resolveImport(
            current: current, incoming: incoming, strategy: .replace, at: importInstant
        )

        #expect(resolved.summary.subscriptions == ImportCounts(removed: 1))
    }

    @Test("merge: an unknown incoming tombstone is applied but counted nowhere")
    func mergeAppliesUnknownTombstoneSilently() throws {
        let current = OttoDataSnapshot(subscriptions: [try subscription(1, updatedAt: older)])
        let incoming = OttoDataSnapshot(
            subscriptions: [try subscription(2, updatedAt: newer, deletedAt: newer)]
        )

        let resolved = try resolveImport(
            current: current, incoming: incoming, strategy: .merge, at: importInstant
        )

        #expect(resolved.snapshot.subscriptions.count == 2)
        #expect(resolved.summary.subscriptions == ImportCounts())
    }

    @Test("merge: a newer tombstone over a live record counts as removed - a deletion propagated")
    func mergeCountsPropagatedDeletionAsRemoved() throws {
        let current = OttoDataSnapshot(subscriptions: [try subscription(1, updatedAt: older)])
        let incoming = OttoDataSnapshot(
            subscriptions: [try subscription(1, updatedAt: newer, deletedAt: newer)]
        )

        let resolved = try resolveImport(
            current: current, incoming: incoming, strategy: .merge, at: importInstant
        )

        #expect(resolved.snapshot.subscriptions.first?.deletedAt == newer)
        #expect(resolved.summary.subscriptions == ImportCounts(removed: 1))
    }

    @Test("merge: a newer live copy over a local tombstone counts as added - the record reappears")
    func mergeCountsResurrectionAsAdded() throws {
        let current = OttoDataSnapshot(
            subscriptions: [try subscription(1, updatedAt: older, deletedAt: older)]
        )
        let incoming = OttoDataSnapshot(subscriptions: [try subscription(1, updatedAt: newer)])

        let resolved = try resolveImport(
            current: current, incoming: incoming, strategy: .merge, at: importInstant
        )

        #expect(resolved.snapshot.subscriptions.first?.deletedAt == nil)
        #expect(resolved.summary.subscriptions == ImportCounts(added: 1))
    }
}
