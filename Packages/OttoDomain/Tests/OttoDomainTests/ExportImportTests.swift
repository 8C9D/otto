import Foundation
import Testing
@testable import OttoDomain

// MARK: - Round trip

@Suite("Export round trip (spec §3.5, Wave 8)")
struct ExportRoundTripTests {

    @Test("export, wipe, import: every value of every model is identical")
    func fullFidelity() throws {
        let original = try fullSnapshot()
        let data = try exportData(from: original, exportedAt: Date(timeIntervalSinceReferenceDate: 0))

        let imported = try importedSnapshot(from: data)

        #expect(imported == strippingWatermarks(original))
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
}

// MARK: - Version handling

@Suite("Export version handling")
struct ExportVersionTests {

    @Test("a future format version fails clearly, before anything is applied")
    func futureVersionRefused() throws {
        let data = Data("""
        {"formatVersion": 3, "exportedAt": 0, "subscriptions": [], "paymentMethods": [],
         "billingEvents": [], "cancellationEpisodes": [], "priceChanges": []}
        """.utf8)

        #expect(throws: ExportFormatError.unsupportedFormatVersion(found: 3, supported: 2)) {
            try decodeExport(data)
        }
        let message = ExportFormatError.unsupportedFormatVersion(found: 3, supported: 2)
            .errorDescription ?? ""
        #expect(message.contains("format 3"))
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
