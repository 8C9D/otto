import Foundation
import Testing
@testable import OttoDomain

// Spec §4a principle 2 (v2.0): invariants are enforced at write and repaired
// at read, never thrown at read. Every shape here is one two correct devices
// produce between them; the repair must be a pure function of the record data
// so both devices converge without coordination.
@Suite("Read repairs (spec §4a, Wave 6B-Prep)")
struct ReadRepairTests {

    private func openEpisode(
        index: Int, startedOn: CalendarDay?, scheduledResumeOn: CalendarDay? = nil
    ) throws -> PauseEpisode {
        PauseEpisode(
            id: try fixtureUUID(index),
            startedOn: startedOn,
            scheduledResumeOn: scheduledResumeOn,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }

    private func repairedPaused(episodes: [PauseEpisode]) throws
    -> (subscription: Subscription, repairs: [SubscriptionReadRepair]) {
        Subscription.readingRepaired(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .paused,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            pauseEpisodes: episodes,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("two open pause episodes: the earliest start wins, the later closes at its own start - zero duration")
    func twoOpenPausesConverge() throws {
        // Both spouses pause the gym membership - device A on Aug 1, device B
        // on Aug 3. Before v2.0 this made the subscription unreadable on every
        // device, permanently. The loser closes AT ITS OWN START (§4a-2a's
        // clamp, v2.1): "closed at the winner's start" would end it before it
        // began, and a zero-duration closure honestly records "recorded,
        // never actually in effect".
        let first = try openEpisode(index: 701, startedOn: try day(2026, 8, 1))
        let second = try openEpisode(index: 702, startedOn: try day(2026, 8, 3))

        let (repaired, repairs) = try repairedPaused(episodes: [first, second])

        let winner = try #require(repaired.currentPauseEpisode)
        #expect(winner.id == first.id)
        let closed = try #require(repaired.pauseEpisodes.first { $0.id == second.id })
        #expect(closed.endedOn == (try day(2026, 8, 3)))
        #expect(closed.outcome == .superseded)
        #expect(repairs == [.extraOpenPauseEpisodeClosed(episodeID: second.id)])

        // Deterministic without coordination: the other device sees the same
        // records in the other order and reaches the identical value.
        let (mirrored, _) = try repairedPaused(episodes: [second, first])
        #expect(Set(mirrored.pauseEpisodes) == Set(repaired.pauseEpisodes))
        #expect(mirrored.currentPauseEpisode?.id == winner.id)
    }

    @Test("no repair can close an episode before its own start - durations are never negative")
    func closureNeverPrecedesStart() throws {
        // Every combination the repair rules can meet: recorded starts in
        // both orders, a nil pre-Wave-7 start on either side, and the
        // status-conflict repair - the first feature to compute pause spans
        // must not meet a negative one (§4a-2a).
        let starts: [CalendarDay?] = [nil, try day(2026, 8, 1), try day(2026, 8, 3), try day(2026, 8, 5)]
        for winnerStart in starts {
            for loserStart in starts {
                let episodes = [
                    try openEpisode(index: 701, startedOn: winnerStart),
                    try openEpisode(index: 702, startedOn: loserStart)
                ]
                let (pausedResult, _) = try repairedPaused(episodes: episodes)
                let (activeResult, _) = Subscription.readingRepaired(
                    id: try fixtureUUID(1),
                    name: "Gym",
                    category: .other,
                    status: .active,
                    amountCents: 4200,
                    currencyCode: "CAD",
                    cycle: .monthly,
                    cycleStartDay: try day(2026, 1, 15),
                    reminderLeadDays: 3,
                    pauseEpisodes: episodes,
                    createdAt: Date(timeIntervalSince1970: 0),
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
                for episode in pausedResult.pauseEpisodes + activeResult.pauseEpisodes {
                    guard let endedOn = episode.endedOn, let startedOn = episode.startedOn else { continue }
                    #expect(endedOn >= startedOn)
                }
            }
        }
    }

    @Test("an open episode beside a stored .active closes at its own start - the status field is authoritative")
    func openEpisodeBesideActiveCloses() throws {
        let episode = try openEpisode(index: 701, startedOn: try day(2026, 8, 3))
        let (repaired, repairs) = Subscription.readingRepaired(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .active,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            pauseEpisodes: [episode],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(repaired.currentPauseEpisode == nil)
        let closed = try #require(repaired.pauseEpisodes.first)
        #expect(closed.endedOn == (try day(2026, 8, 3)))
        #expect(closed.outcome == .superseded)
        #expect(repairs == [.conflictingOpenPauseEpisodeClosed(episodeID: episode.id)])
    }

    @Test(".paused with no open episode holds as an indefinite pause - nothing invented, nothing billed")
    func pausedWithoutEpisodeHolds() throws {
        let (repaired, repairs) = try repairedPaused(episodes: [])

        #expect(repaired.storedStatus == .paused)
        #expect(repaired.currentPauseEpisode == nil)
        #expect(repaired.pauseEndsOn == nil)
        // Reads as an indefinite pause: never derives a resume, expects no
        // charges, freezes the watermark - the safest honest reading until
        // the episode record arrives and completes the aggregate.
        #expect(repaired.effectiveStatus(asOf: try day(2027, 1, 1)) == .paused)
        #expect(expectedCharges(
            for: repaired, from: try day(2026, 1, 1), through: try day(2027, 1, 1),
            asOf: try day(2026, 8, 7)
        ) == [])
        #expect(repairs == [.pausedWithoutOpenEpisode])
    }

    @Test("a valid value repairs nothing and equals the plain construction")
    func validShapePassesThrough() throws {
        let episode = try openEpisode(index: 701, startedOn: try day(2026, 8, 1))
        let (repaired, repairs) = try repairedPaused(episodes: [episode])

        #expect(repairs == [])
        #expect(repaired.pauseEpisodes == [episode])
        #expect(repaired.currentPauseEpisode?.id == episode.id)
    }

    @Test("the describing constructor holds the one editable degraded shape: live .paused with no open episode")
    func describingHoldsDegradedPaused() throws {
        // Spec §4a principle 2b (v2.1): the edit path re-describes a degraded
        // record through a WRITE constructor whose tolerance is scoped to
        // exactly this shape - never through readingRepaired, whose blanket
        // permissiveness would let repair-rule changes silently alter write
        // validation.
        let described = Subscription.describing(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .paused,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            pauseEpisodes: [],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        // The same indefinite-pause reading the repaired read produces.
        #expect(described.storedStatus == .paused)
        #expect(described.currentPauseEpisode == nil)
        #expect(described.effectiveStatus(asOf: try day(2027, 1, 1)) == .paused)
    }

    @Test("for a healthy shape the describing constructor is the plain init")
    func describingEqualsInitForHealthyShapes() throws {
        let episode = try openEpisode(index: 701, startedOn: try day(2026, 8, 1))
        let described = Subscription.describing(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .paused,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            pauseEpisodes: [episode],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let constructed = Subscription(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .paused,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            pauseEpisodes: [episode],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(described == constructed)
    }

    @Test("a tombstoned subscription's episodes are history, not violations - no status-coupled repair runs")
    func tombstonedWholeIsUntouched() throws {
        let episode = try openEpisode(index: 701, startedOn: try day(2026, 8, 1))
        let (repaired, repairs) = Subscription.readingRepaired(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .active,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            pauseEpisodes: [episode],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            deletedAt: Date(timeIntervalSince1970: 9_000)
        )

        // Wave 8.5's lesson, upheld by the repair path: tombstones are outside
        // every status-coupled invariant, so the open episode rides along.
        #expect(repairs == [])
        #expect(repaired.pauseEpisodes.first?.endedOn == nil)
    }
}
