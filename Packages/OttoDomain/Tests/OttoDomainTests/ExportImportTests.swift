import Foundation
import Testing
@testable import OttoDomain

/// R3-1's predicate, where it lives. The watermark policy asks "does this
/// device have ledger progress worth keeping", and `isEmpty` answered a
/// different question - whether there is anything to merge WITH - which a
/// database full of tombstones answers "yes" to.
@Suite("A snapshot with no live subscriptions (R3-1)")
struct LiveSubscriptionPredicateTests {

    @Test("an empty snapshot has no live subscriptions")
    func emptySnapshot() {
        let snapshot = OttoDataSnapshot()
        #expect(snapshot.isEmpty)
        #expect(snapshot.hasNoLiveSubscriptions)
    }

    @Test("⛔ a tombstoned subscription beside a LIVE payment method still counts as no progress")
    func tombstonedSubscriptionWithSurvivingCard() throws {
        // The state a user actually reaches: `deleteSubscription` cascades to
        // trials, episodes, billing events and price changes, but a payment
        // method is not a child of a subscription and survives. A predicate
        // that demanded every record type be tombstoned would answer
        // "something is live" here and leave the watermarks nil.
        var snapshot = try fullSnapshot()
        let buriedAt = Date(timeIntervalSince1970: 9_000)
        for index in snapshot.subscriptions.indices {
            snapshot.subscriptions[index].deletedAt = buriedAt
        }
        #expect(!snapshot.paymentMethods.isEmpty)
        #expect(snapshot.paymentMethods.contains { $0.deletedAt == nil })
        #expect(!snapshot.isEmpty)
        #expect(snapshot.hasNoLiveSubscriptions)
    }

    @Test("one live subscription is progress worth keeping, however much else is tombstoned")
    func oneLiveSubscriptionIsEnough() throws {
        var snapshot = try fullSnapshot()
        let buriedAt = Date(timeIntervalSince1970: 9_000)
        for index in snapshot.subscriptions.indices where index > 0 {
            snapshot.subscriptions[index].deletedAt = buriedAt
        }
        for index in snapshot.billingEvents.indices { snapshot.billingEvents[index].deletedAt = buriedAt }
        for index in snapshot.paymentMethods.indices { snapshot.paymentMethods[index].deletedAt = buriedAt }
        #expect(snapshot.subscriptions.contains { $0.deletedAt == nil })
        #expect(!snapshot.hasNoLiveSubscriptions)
    }
}

// MARK: - Round trip

@Suite("Export round trip (spec §3.5, Wave 8)")
struct ExportRoundTripTests {

    @Test("export, wipe, import: every value of every model is identical")
    func fullFidelity() throws {
        let original = try fullSnapshot()
        let data = try exportData(from: original, exportedAt: Date(timeIntervalSinceReferenceDate: 0))

        let imported = try importedSnapshot(from: data)

        #expect(imported == original)
    }

    @Test("an empty database exports and imports without special-casing")
    func emptyDatabase() throws {
        let data = try exportData(from: OttoDataSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let imported = try importedSnapshot(from: data)
        #expect(imported == OttoDataSnapshot())
        #expect(imported.isEmpty)
    }

    @Test("identical databases export identical bytes")
    func deterministicBytes() throws {
        let exportedAt = Date(timeIntervalSinceReferenceDate: 0)
        let first = try exportData(from: try fullSnapshot(), exportedAt: exportedAt)
        let second = try exportData(from: try fullSnapshot(), exportedAt: exportedAt)
        #expect(first == second)
    }

    @Test("the device-local watermark is absent from the export by design (spec §5.3)")
    func watermarkAbsent() throws {
        let data = try exportData(from: try fullSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("lastMaterializedThrough"))
        #expect(!text.contains("MaterializedThrough"))
    }
}

// MARK: - The frozen wire strings

@Suite("Wire format v1 is frozen")
struct WireFormatTests {

    @Test("every enum value serializes as its pinned v1 string")
    func pinnedEnumStrings() throws {
        // These strings ARE format v1. A domain rename must not change them; if
        // one ever must, that is a format version bump with migration, and this
        // test is the tripwire that says so.
        #expect(SubscriptionStatus.allCases.map(\.rawValue) == [
            "trial", "active", "paused", "cancellationPending", "cancelled", "archived"
        ])
        #expect(BillingCycle.Unit.allCases.map(\.rawValue) == ["day", "week", "month", "year"])
        #expect(BillingEvent.State.allCases.map(\.rawValue) == [
            "upcoming", "confirmedCharged", "confirmedNotCharged", "unexpectedCharge", "skipped"
        ])
        #expect(CancellationEpisode.VerificationState.allCases.map(\.rawValue) == [
            "pending", "stillCharging", "needsManualReview", "awaitingResumeDate"
        ])
        // The outcome enums were missing from this freeze until the Wave
        // 6B-Prep-2 sweep - stored and exported episodes carry these forever,
        // `.superseded` included even though v2.1 stopped writing it.
        #expect(CancellationEpisode.Outcome.allCases.map(\.rawValue) == [
            "verifiedStopped", "abandoned", "superseded"
        ])
        #expect(PauseEpisode.Outcome.allCases.map(\.rawValue) == ["resumed", "superseded"])
        #expect(PriceChange.Source.allCases.map(\.rawValue) == [
            "userEdit", "chargeMismatch", "trialConversion"
        ])
        #expect(OttoDomain.Category.allCases.map(\.rawValue) == [
            "streaming-and-video", "music-and-audio", "news-and-reading",
            "ai-and-software-tools", "cloud-and-storage", "gaming",
            "fitness-and-health", "food-and-delivery", "shopping-and-memberships",
            "phone-and-internet", "finance-and-insurance", "education-and-courses",
            "other"
        ])
    }

    @Test("calendar days are YYYY-MM-DD strings on the wire")
    func calendarDayShape() throws {
        let data = try exportData(from: try fullSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"cycleStartDay\" : \"2024-01-31\""))
    }

    @Test("a fresh export writes the evidenceNotes array and never the pre-v3 key")
    func evidenceNotesWireShape() throws {
        let data = try exportData(from: try fullSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"evidenceNotes\" :"))
        #expect(!text.contains("\"evidenceNote\" :"))
    }

    @Test("instants are ISO 8601 UTC strings on the wire - never the 2001-epoch numbers (v4)")
    func instantsAreISO8601Strings() throws {
        // The Wave 9A hands-on session read "createdAt": 807839382.279346 in a
        // real export - Apple's reference epoch, 31 years wrong to any importer
        // that assumes Unix seconds. Format v4 forbids the shape entirely.
        let data = try exportData(from: try fullSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("\"formatVersion\" : 4"))
        #expect(text.contains("\"exportedAt\" : \"2001-01-01T00:00:00.000Z\""))
        #expect(text.contains("\"createdAt\" : \"2025-08-08T00:00:00.500Z\""))
        // Every instant key ends in "At"; none may carry a bare number.
        #expect(text.range(of: #"At" : \d"#, options: .regularExpression) == nil)
        #expect(text.range(of: #"At" : -"#, options: .regularExpression) == nil)
    }

    @Test("a sub-millisecond fraction truncates to the millisecond - v4's documented cost, never more")
    func subMillisecondTruncation() throws {
        // The one thing v4 gave up for portability, pinned so it can never
        // silently grow: an instant loses at most its sub-millisecond digits.
        let precise = Date(timeIntervalSinceReferenceDate: 807_839_382.279346)
        let snapshot = OttoDataSnapshot(paymentMethods: [PaymentMethod(
            id: try fixtureUUID(1), label: "Card", last4: "4242", issuer: "Visa",
            expiryMonth: 12, expiryYear: 2028, isDefault: true,
            createdAt: precise, updatedAt: precise
        )])

        let data = try exportData(from: snapshot, exportedAt: precise)
        let imported = try importedSnapshot(from: data)

        let method = try #require(imported.paymentMethods.first)
        let drift = abs(method.createdAt.timeIntervalSince(precise))
        #expect(drift > 0)
        #expect(drift < 0.001)
    }
}

// MARK: - Version handling

@Suite("Export version handling")
struct ExportVersionTests {

    @Test("a future format version fails clearly, before anything is applied")
    func futureVersionRefused() throws {
        let data = Data("""
        {"formatVersion": 5, "exportedAt": "2026-08-07T00:00:00.000Z", "subscriptions": [],
         "paymentMethods": [], "billingEvents": [], "cancellationEpisodes": [], "priceChanges": []}
        """.utf8)

        #expect(throws: ExportFormatError.unsupportedFormatVersion(found: 5, supported: 4)) {
            try decodeExport(data)
        }
        let message = ExportFormatError.unsupportedFormatVersion(found: 5, supported: 4)
            .errorDescription ?? ""
        #expect(message.contains("format 5"))
        #expect(message.contains("Nothing was changed"))
    }

    @Test("bytes without a formatVersion are refused as unreadable")
    func versionlessRefused() throws {
        #expect(throws: ExportFormatError.self) { try decodeExport(Data("{}".utf8)) }
        #expect(throws: ExportFormatError.self) { try decodeExport(Data("not json".utf8)) }
        #expect(throws: ExportFormatError.self) { try decodeExport(Data()) }
    }

    @Test("the current version decodes")
    func currentVersionAccepted() throws {
        let data = try exportData(from: OttoDataSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let export = try decodeExport(data)
        #expect(export.formatVersion == OttoExport.currentFormatVersion)
    }

    @Test("a damaged field is refused with the entity named, never half-applied")
    func damagedValueRefused() throws {
        let data = try exportData(from: try fullSnapshot(), exportedAt: Date(timeIntervalSinceReferenceDate: 0))
        let text = try #require(String(data: data, encoding: .utf8))
        let corrupted = Data(text.replacingOccurrences(
            of: "\"cycleStartDay\" : \"2024-01-31\"",
            with: "\"cycleStartDay\" : \"2024-13-99\""
        ).utf8)

        #expect(throws: ExportFormatError.self) { try importedSnapshot(from: corrupted) }
    }
}
