import Foundation
import Testing
@testable import OttoDomain

// A REAL format-v1 file, frozen as bytes: the shape every pre-8.5 export has,
// with the single pausedOn/pauseEndsOn pair and the top-level
// cancellationRecords array. Importing it must keep working forever - after
// Wave 6 an old export may be somebody's only copy of their data.
private let v1File = Data("""
{
  "formatVersion" : 1,
  "exportedAt" : 776304000,
  "subscriptions" : [
    {
      "id" : "00000000-0000-0000-0000-000000000001",
      "name" : "Gym",
      "category" : "fitness-and-health",
      "status" : "paused",
      "amountCents" : 4200,
      "currencyCode" : "CAD",
      "cycleUnit" : "month",
      "cycleInterval" : 1,
      "cycleStartDay" : "2026-02-10",
      "reminderLeadDays" : 3,
      "sameDayReminder" : false,
      "pausedOn" : "2026-06-01",
      "pauseEndsOn" : "2026-12-01",
      "createdAt" : 776304000.5,
      "updatedAt" : 776390412.25
    },
    {
      "id" : "00000000-0000-0000-0000-000000000002",
      "name" : "Legacy pause",
      "category" : "other",
      "status" : "paused",
      "amountCents" : 1099,
      "currencyCode" : "CAD",
      "cycleUnit" : "month",
      "cycleInterval" : 1,
      "cycleStartDay" : "2026-01-15",
      "reminderLeadDays" : 3,
      "sameDayReminder" : false,
      "createdAt" : 776304000,
      "updatedAt" : 776390412
    },
    {
      "id" : "00000000-0000-0000-0000-000000000003",
      "name" : "Cancelled",
      "category" : "streaming-and-video",
      "status" : "cancellationPending",
      "amountCents" : 1899,
      "currencyCode" : "CAD",
      "cycleUnit" : "month",
      "cycleInterval" : 1,
      "cycleStartDay" : "2026-03-01",
      "reminderLeadDays" : 3,
      "sameDayReminder" : false,
      "createdAt" : 776304000,
      "updatedAt" : 776390412
    },
    {
      "id" : "00000000-0000-0000-0000-000000000004",
      "name" : "Archived",
      "category" : "gaming",
      "status" : "archived",
      "amountCents" : 999,
      "currencyCode" : "CAD",
      "cycleUnit" : "month",
      "cycleInterval" : 1,
      "cycleStartDay" : "2026-04-01",
      "reminderLeadDays" : 3,
      "sameDayReminder" : false,
      "createdAt" : 776304000,
      "updatedAt" : 776390412
    }
  ],
  "paymentMethods" : [],
  "billingEvents" : [],
  "cancellationRecords" : [
    {
      "id" : "00000000-0000-0000-0000-000000000601",
      "subscriptionID" : "00000000-0000-0000-0000-000000000003",
      "markedCancelledAt" : 776304100,
      "nextChargeDateIfNotCancelled" : "2026-09-01",
      "expectedChargeAmountCents" : 1899,
      "verificationState" : "pending",
      "unansweredCheckCount" : 0,
      "createdAt" : 776304100,
      "updatedAt" : 776304100
    },
    {
      "id" : "00000000-0000-0000-0000-000000000602",
      "subscriptionID" : "00000000-0000-0000-0000-000000000004",
      "markedCancelledAt" : 776304200,
      "nextChargeDateIfNotCancelled" : "2026-05-01",
      "verificationState" : "verifiedStopped",
      "unansweredCheckCount" : 0,
      "verifiedAt" : 776350000,
      "createdAt" : 776304200,
      "updatedAt" : 776360000
    }
  ],
  "priceChanges" : []
}
""".utf8)

@Suite("Importing a format-v1 file (spec §3.5's documented defaults)")
struct ExportLegacyImportTests {

    @Test("a v1 pause pair becomes one open episode; a pre-v1.7 pause still gets its episode")
    func pausePairUpgrades() throws {
        let snapshot = try importedSnapshot(from: v1File)

        let gym = try #require(snapshot.subscriptions.first { $0.name == "Gym" })
        let episode = try #require(gym.currentPauseEpisode)
        #expect(gym.pauseEpisodes.count == 1)
        #expect(episode.startedOn == (try day(2026, 6, 1)))
        #expect(episode.scheduledResumeOn == (try day(2026, 12, 1)))
        #expect(episode.outcome == nil)
        // Timestamps are borrowed from the subscription - the closest instant
        // v1 recorded to the pause actually starting.
        #expect(episode.createdAt == gym.updatedAt)

        // A record paused before Wave 7 recorded neither date; the §5.3a
        // invariant still requires its open episode, with honest nils.
        let legacy = try #require(snapshot.subscriptions.first { $0.name == "Legacy pause" })
        let legacyEpisode = try #require(legacy.currentPauseEpisode)
        #expect(legacyEpisode.startedOn == nil)
        #expect(legacyEpisode.scheduledResumeOn == nil)

        // Statuses with no pause state get no episode invented for them.
        let cancelled = try #require(snapshot.subscriptions.first { $0.name == "Cancelled" })
        #expect(cancelled.pauseEpisodes.isEmpty)
    }

    @Test("re-importing the same v1 file cannot duplicate the synthesized episode - its id is derived")
    func synthesizedEpisodeIDIsStable() throws {
        let first = try importedSnapshot(from: v1File)
        let second = try importedSnapshot(from: v1File)
        #expect(first == second)

        // And merging the second import over the first changes nothing: same
        // ids, same updatedAt, tie keeps existing.
        let resolved = try resolveImport(current: first, incoming: second, strategy: .merge)
        #expect(resolved.snapshot == first)
    }

    @Test("v1 cancellation records upgrade by one rule: verified-stopped closes, everything else stays open")
    func cancellationRecordsUpgrade() throws {
        let snapshot = try importedSnapshot(from: v1File)
        #expect(snapshot.cancellationEpisodes.count == 2)

        let pending = try #require(snapshot.cancellationEpisodes.first { $0.id == (try fixtureUUID(601)) })
        #expect(pending.isOpen)
        #expect(pending.outcome == nil)
        // v1 never captured what the cancellation interrupted.
        #expect(pending.statusAtStart == nil)

        let verified = try #require(snapshot.cancellationEpisodes.first { $0.id == (try fixtureUUID(602)) })
        #expect(!verified.isOpen)
        #expect(verified.outcome == .verifiedStopped)
        // Closed at its verification instant (CancellationEpisode.legacyClosure).
        #expect(verified.endedAt == verified.verifiedAt)
    }

    @Test("a v2 file's episodes round-trip verbatim - the upgrade never runs on current data")
    func upgradeGatedOnVersion() throws {
        // An open verified-stopped episode cannot come from Otto's flows, but a
        // v2 file's data must round-trip as written, not be "repaired" by the
        // v1 rule. Encode a v2 export whose episode WOULD change if the legacy
        // closure ran, and check it comes back untouched.
        let episode = CancellationEpisode(
            id: try fixtureUUID(603),
            subscriptionID: try fixtureUUID(1),
            markedCancelledAt: Date(timeIntervalSinceReferenceDate: 776_304_100),
            nextChargeDateIfNotCancelled: try day(2026, 9, 1),
            verificationState: .verifiedStopped,
            verifiedAt: Date(timeIntervalSinceReferenceDate: 776_350_000),
            createdAt: Date(timeIntervalSinceReferenceDate: 776_304_100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 776_360_000)
        )
        let subscription = Subscription(
            id: try fixtureUUID(1),
            name: "S",
            category: .other,
            status: .active,
            amountCents: 1000,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 1),
            reminderLeadDays: 3,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let snapshot = OttoDataSnapshot(subscriptions: [subscription], cancellationEpisodes: [episode])
        let data = try exportData(from: snapshot, exportedAt: Date(timeIntervalSinceReferenceDate: 0))

        let imported = try importedSnapshot(from: data)

        let roundTripped = try #require(imported.cancellationEpisodes.first)
        #expect(roundTripped.isOpen)
        #expect(roundTripped.outcome == nil)
    }
}
