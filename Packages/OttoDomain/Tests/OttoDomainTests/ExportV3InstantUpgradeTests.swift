import Foundation
import Testing
@testable import OttoDomain

// A REAL format-v3 file, frozen as bytes: the shape every export before Wave
// 9A had, with instants as JSON numbers of seconds since 2001-01-01T00:00:00Z.
// The fractional createdAt is the literal value the first hands-on session
// read in a real export (spec §9b defect 3). These files must import forever.
private let v3File = Data("""
{
  "formatVersion" : 3,
  "exportedAt" : 807839400,
  "subscriptions" : [
    {
      "id" : "00000000-0000-0000-0000-000000000001",
      "name" : "Subscription C",
      "category" : "ai-and-software-tools",
      "status" : "active",
      "amountCents" : 10488,
      "currencyCode" : "CAD",
      "cycleUnit" : "year",
      "cycleInterval" : 1,
      "cycleStartDay" : "2026-10-06",
      "reminderLeadDays" : 3,
      "sameDayReminder" : false,
      "pauseEpisodes" : [],
      "createdAt" : 807839382.279346,
      "updatedAt" : 807839382.279346
    }
  ],
  "paymentMethods" : [
    {
      "id" : "00000000-0000-0000-0000-000000000010",
      "label" : "Credit card",
      "last4" : "4242",
      "issuer" : "Visa",
      "expiryMonth" : 12,
      "expiryYear" : 2028,
      "isDefault" : true,
      "createdAt" : 776304000.5,
      "updatedAt" : 776390412.25
    }
  ],
  "billingEvents" : [
    {
      "id" : "00000000-0000-0000-0000-000000000020",
      "subscriptionID" : "00000000-0000-0000-0000-000000000001",
      "expectedDate" : "2026-10-06",
      "expectedAmountCents" : 10488,
      "state" : "upcoming",
      "createdAt" : 807839382,
      "updatedAt" : 807839382
    }
  ],
  "cancellationEpisodes" : [
    {
      "id" : "00000000-0000-0000-0000-000000000030",
      "subscriptionID" : "00000000-0000-0000-0000-000000000001",
      "markedCancelledAt" : 776304100,
      "statusAtStart" : "active",
      "nextChargeDateIfNotCancelled" : "2026-09-01",
      "expectedChargeAmountCents" : 10488,
      "verificationState" : "pending",
      "unansweredCheckCount" : 0,
      "evidenceNotes" : [
        {
          "id" : "00000000-0000-0000-0000-000000000031",
          "text" : "conf #V3-123",
          "createdAt" : 776304100,
          "updatedAt" : 776304100
        }
      ],
      "endedAt" : 776360000,
      "outcome" : "abandoned",
      "createdAt" : 776304100,
      "updatedAt" : 776360000
    }
  ],
  "priceChanges" : [
    {
      "id" : "00000000-0000-0000-0000-000000000040",
      "subscriptionID" : "00000000-0000-0000-0000-000000000001",
      "effectiveDate" : "2026-10-06",
      "oldAmountCents" : 8990,
      "newAmountCents" : 10488,
      "source" : "userEdit",
      "createdAt" : 776304200,
      "updatedAt" : 776304200
    }
  ]
}
""".utf8)

@Suite("Importing a format-v3 file after the v4 instant change (spec §9b defect 3)")
struct ExportV3InstantUpgradeTests {

    @Test("v3's 2001-epoch numeric instants decode bit-exactly, forever")
    func numericInstantsDecode() throws {
        let snapshot = try importedSnapshot(from: v3File)

        let subscription = try #require(snapshot.subscriptions.first)
        #expect(subscription.createdAt == Date(timeIntervalSinceReferenceDate: 807_839_382.279346))
        let method = try #require(snapshot.paymentMethods.first)
        #expect(method.createdAt == Date(timeIntervalSinceReferenceDate: 776_304_000.5))
        #expect(method.updatedAt == Date(timeIntervalSinceReferenceDate: 776_390_412.25))
        let episode = try #require(snapshot.cancellationEpisodes.first)
        #expect(episode.endedAt == Date(timeIntervalSinceReferenceDate: 776_360_000))
    }

    @Test("a real v3 file round-trips into v4: ISO instants out, nothing else changed")
    func v3RoundTripsIntoV4() throws {
        let imported = try importedSnapshot(from: v3File)
        let exportedAt = Date(timeIntervalSinceReferenceDate: 807_839_400)

        let v4Data = try exportData(from: imported, exportedAt: exportedAt)
        let text = try #require(String(data: v4Data, encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 4"))
        // The exact instant the hands-on session read as 807839382.279346,
        // now legible to any ISO 8601 reader; millisecond precision is the
        // documented cost of leaving the platform epoch.
        #expect(text.contains("\"createdAt\" : \"2026-08-07T23:49:42.279Z\""))
        #expect(text.contains("\"updatedAt\" : \"2025-08-09T00:00:12.250Z\""))
        #expect(text.range(of: #"At" : \d"#, options: .regularExpression) == nil)

        let reimported = try importedSnapshot(from: v4Data)
        // Sub-millisecond truncation is the ONLY permitted difference.
        let subscription = try #require(reimported.subscriptions.first)
        let original = try #require(imported.subscriptions.first)
        #expect(abs(subscription.createdAt.timeIntervalSince(original.createdAt)) < 0.001)
        #expect(subscription.cycleStartDay == original.cycleStartDay)
        #expect(subscription.amountCents == original.amountCents)

        // And v4 is self-stable: once through, re-exporting reproduces the
        // same bytes - the round trip loses nothing further, ever.
        let v4Again = try exportData(from: reimported, exportedAt: exportedAt)
        #expect(v4Again == v4Data)
    }

    @Test("a v4 file carrying numeric instants is damaged, not tolerated")
    func v4NumericInstantsRefused() throws {
        // Leniency here would let the platform epoch quietly re-enter the wire
        // format the moment some writer regresses.
        let data = Data("""
        {"formatVersion": 4, "exportedAt": 807839400, "subscriptions": [],
         "paymentMethods": [], "billingEvents": [], "cancellationEpisodes": [], "priceChanges": []}
        """.utf8)
        #expect(throws: ExportFormatError.self) { try decodeExport(data) }
    }
}
