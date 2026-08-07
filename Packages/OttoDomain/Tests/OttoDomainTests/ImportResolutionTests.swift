import Foundation
import Testing
@testable import OttoDomain

// MARK: - Import resolution

@Suite("Import conflict policy (Wave 8: explicit, never silent)")
struct ImportResolutionTests {

    private let older = Date(timeIntervalSinceReferenceDate: 100)
    private let newer = Date(timeIntervalSinceReferenceDate: 200)

    private func subscription(_ index: Int, updatedAt: Date, name: String = "Sub",
                              watermark: CalendarDay? = nil) throws -> Subscription {
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
            lastMaterializedThrough: watermark,
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

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge)

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
            current: current, incoming: try importedSnapshot(from: data), strategy: .merge
        )

        #expect(resolved.snapshot == current)
        #expect(resolved.summary.subscriptions.added == 0)
        #expect(resolved.summary.subscriptions.updated == 0)
    }

    @Test("a merged update never touches the stored watermark (spec §5.3)")
    func mergePreservesWatermark() throws {
        let current = OttoDataSnapshot(subscriptions: [
            try subscription(1, updatedAt: older, name: "local", watermark: try day(2026, 9, 1))
        ])
        let incoming = OttoDataSnapshot(subscriptions: [
            try subscription(1, updatedAt: newer, name: "imported")
        ])

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge)

        #expect(resolved.snapshot.subscriptions.first?.name == "imported")
        #expect(resolved.snapshot.subscriptions.first?.lastMaterializedThrough == (try day(2026, 9, 1)))
    }

    @Test("replace becomes exactly the file, and counts what it removed")
    func replaceIsExact() throws {
        let current = OttoDataSnapshot(subscriptions: [
            try subscription(1, updatedAt: older),
            try subscription(2, updatedAt: older)
        ])
        let incoming = OttoDataSnapshot(subscriptions: [try subscription(3, updatedAt: newer)])

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .replace)

        #expect(resolved.snapshot == incoming)
        #expect(resolved.summary.subscriptions == ImportCounts(added: 1, removed: 2))
    }

    @Test("two open cancellations for one subscription keep both - the older closes as superseded")
    func singleOpenCancellation() throws {
        // Each side cancelled independently, so the merge unites two OPEN
        // episodes. v1's single slot discarded the loser outright; the episode
        // table keeps both (spec §5.3a) - the newest stays the current watch
        // and the older closes as `.superseded`, counted, never silent.
        let sub = try subscription(1, updatedAt: older)
        func episode(_ index: Int, markedCancelledAt: Date) throws -> CancellationEpisode {
            CancellationEpisode(
                id: try fixtureUUID(index),
                subscriptionID: sub.id,
                markedCancelledAt: markedCancelledAt,
                nextChargeDateIfNotCancelled: try day(2026, 9, 1),
                verificationState: .pending,
                createdAt: older,
                updatedAt: markedCancelledAt
            )
        }
        let current = OttoDataSnapshot(
            subscriptions: [sub], cancellationEpisodes: [try episode(601, markedCancelledAt: older)]
        )
        let incoming = OttoDataSnapshot(
            subscriptions: [sub], cancellationEpisodes: [try episode(602, markedCancelledAt: newer)]
        )

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge)

        #expect(resolved.snapshot.cancellationEpisodes.count == 2)
        let open = resolved.snapshot.cancellationEpisodes.filter(\.isOpen)
        #expect(open.map(\.id) == [try fixtureUUID(602)])
        let closed = try #require(
            resolved.snapshot.cancellationEpisodes.first { $0.id == (try fixtureUUID(601)) }
        )
        #expect(closed.outcome == .superseded)
        #expect(closed.endedAt == newer)
        #expect(resolved.summary.cancellationEpisodes.removed == 0)
        // Added (the incoming episode) plus updated (the superseded closure).
        #expect(resolved.summary.cancellationEpisodes.added == 1)
        #expect(resolved.summary.cancellationEpisodes.updated == 1)
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

        let resolved = try resolveImport(current: current, incoming: incoming, strategy: .merge)

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
            try resolveImport(current: OttoDataSnapshot(), incoming: incoming, strategy: .replace)
        }
    }
}
