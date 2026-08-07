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
      "evidenceNote" : "conf #V1-777",
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
        let resolved = try resolveImport(
            current: first, incoming: second, strategy: .merge,
            at: Date(timeIntervalSinceReferenceDate: 900)
        )
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
        // The single v1 evidence string became one note (spec §5.4, v1.9):
        // derived id, timestamps borrowed from the episode, so re-importing
        // the same file cannot duplicate it.
        let note = try #require(pending.evidenceNotes.first)
        #expect(pending.evidenceNotes.count == 1)
        #expect(note.text == "conf #V1-777")
        #expect(note.createdAt == pending.updatedAt)
        #expect(note.id == EvidenceNote.legacyNote(
            episodeID: pending.id, text: "", episodeUpdatedAt: pending.updatedAt
        ).id)
        // The literal, not just the rule: the XOR mask is frozen wire format.
        // A mask change would keep the rule-vs-rule check green while every
        // re-import of an old file after an app update duplicated its notes.
        // Pinned by the Wave 6B-Prep-2 sweep.
        #expect(note.id == UUID(uuidString: "45766964-4E6F-7465-0000-000000000601"))

        let verified = try #require(snapshot.cancellationEpisodes.first { $0.id == (try fixtureUUID(602)) })
        #expect(!verified.isOpen)
        #expect(verified.outcome == .verifiedStopped)
        // Closed at its verification instant (CancellationEpisode.legacyClosure).
        #expect(verified.endedAt == verified.verifiedAt)
    }

    @Test("a v2 file carrying the pre-fold verifiedStopped STATE upgrades at read (spec §5.4, v1.9)")
    func preFoldStateUpgradesAtRead() throws {
        // Files written before v1.9 carry "verifiedStopped" in
        // `verificationState` - the case the folding removed from the domain.
        // The domain can no longer even construct it, so the fixture edits the
        // raw JSON the way a pre-fold Otto wrote it: an OPEN episode whose
        // state claims verified-stopped (pre-fold semantics: finished). The
        // upgrade must close it at its verification instant - the same
        // `legacyClosure` rule v1 files use - and park the vestigial live
        // state at `.pending`.
        let episode = CancellationEpisode(
            id: try fixtureUUID(603),
            subscriptionID: try fixtureUUID(1),
            markedCancelledAt: Date(timeIntervalSinceReferenceDate: 776_304_100),
            nextChargeDateIfNotCancelled: try day(2026, 9, 1),
            verificationState: .pending,
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
        let preFoldJSON = try #require(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"pending\"", with: "\"verifiedStopped\"")
        let preFoldData = try #require(preFoldJSON.data(using: .utf8))

        let imported = try importedSnapshot(from: preFoldData)

        let upgraded = try #require(imported.cancellationEpisodes.first)
        #expect(!upgraded.isOpen)
        #expect(upgraded.outcome == .verifiedStopped)
        #expect(upgraded.endedAt == upgraded.verifiedAt)
        #expect(upgraded.verificationState == .pending)
    }

    @Test("a v2 file's CLOSED verified episode keeps its closure and sheds only the pre-fold state")
    func preFoldClosedStateRemapsOnly() throws {
        // The common pre-fold shape: verification passed, so the single writer
        // both set the state AND closed the episode. Only the state needs
        // upgrading; the closure must come through untouched.
        let ended = Date(timeIntervalSinceReferenceDate: 776_350_000)
        let episode = CancellationEpisode(
            id: try fixtureUUID(603),
            subscriptionID: try fixtureUUID(1),
            markedCancelledAt: Date(timeIntervalSinceReferenceDate: 776_304_100),
            nextChargeDateIfNotCancelled: try day(2026, 9, 1),
            verificationState: .pending,
            verifiedAt: ended,
            endedAt: ended,
            outcome: .verifiedStopped,
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
        let preFoldJSON = try #require(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"pending\"", with: "\"verifiedStopped\"")
        let preFoldData = try #require(preFoldJSON.data(using: .utf8))

        let imported = try importedSnapshot(from: preFoldData)

        let upgraded = try #require(imported.cancellationEpisodes.first)
        #expect(upgraded.endedAt == ended)
        #expect(upgraded.outcome == .verifiedStopped)
        #expect(upgraded.verificationState == .pending)
    }
}
