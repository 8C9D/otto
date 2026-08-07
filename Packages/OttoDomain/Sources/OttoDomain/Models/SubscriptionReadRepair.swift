import Foundation

/// One deterministic repair a §4a read applied (spec §4a principle 2, Wave
/// 6B-Prep). Under per-record sync, any invariant reachable from two devices
/// WILL be violated by two correct devices acting independently; a read that
/// throws on the result converts a sync artifact into a permanently dead
/// record. Reads therefore repair - by rules that are pure functions of the
/// record data, so every device reaches the same value without coordination -
/// and report what they did, so a lossy repair surfaces in Today's aggregate
/// needs-review card instead of being decided silently.
public enum SubscriptionReadRepair: Hashable, Sendable {
    /// Two (or more) live open pause episodes - both devices paused
    /// independently. The earliest start wins; this later episode was closed
    /// at the winner's start as `.superseded` - clamped to its own start
    /// (§4a-2a: a closed episode may never end before it starts), so it
    /// records zero duration: recorded, never actually in effect. Lossy: the
    /// episode was open.
    case extraOpenPauseEpisodeClosed(episodeID: UUID)
    /// A live open episode beside a stored `.active` or `.trial` - a resume on
    /// one device racing a pause on the other. The parent record's status is
    /// authoritative (it is the single field both devices converge on); the
    /// episode was closed at its own start as `.superseded`. Lossy: the
    /// episode was open.
    case conflictingOpenPauseEpisodeClosed(episodeID: UUID)
    /// `.paused` with no open episode - the parent arrived before its episode
    /// record. Read as an indefinite pause (bills nothing, watermark frozen);
    /// self-heals when the episode syncs in. Nothing is invented.
    case pausedWithoutOpenEpisode
    /// `.trial` with no live term - the parent arrived before its trial
    /// record. Read as a trial that never reaches conversion (no reminder, no
    /// materialized charge); self-heals when the term syncs in. Nothing is
    /// invented.
    case trialWithoutTerm
}

/// One subscription's repairs, as the repository reports them for the
/// aggregate needs-review card (spec §5.2b) - the same recompute-on-read shape
/// as `unreadableSubscriptionCount`.
public struct SubscriptionReadRepairReport: Hashable, Sendable, Identifiable {
    public let subscriptionID: UUID
    public let name: String
    public let repairs: [SubscriptionReadRepair]

    public var id: UUID { subscriptionID }

    public init(subscriptionID: UUID, name: String, repairs: [SubscriptionReadRepair]) {
        self.subscriptionID = subscriptionID
        self.name = name
        self.repairs = repairs
    }
}

extension Subscription {
    /// The §4a READ construction: same fields as `init`, but shapes the
    /// write-time preconditions would trap on are repaired deterministically
    /// (or, for the two incomplete-aggregate shapes, held as they are) and
    /// reported. This is the only way such a value can exist in process; every
    /// read of stored or wire data comes through here, and every write path
    /// still goes through the preconditioned `init`.
    /// (Parameter count mirrors `init` - the two must stay field-for-field.)
    public static func readingRepaired( // swiftlint:disable:this function_parameter_count
        id: UUID,
        name: String,
        vendorURL: URL? = nil,
        category: Category,
        status: SubscriptionStatus,
        amountCents: Int,
        currencyCode: String,
        cycle: BillingCycle,
        cycleStartDay: CalendarDay,
        reminderLeadDays: Int,
        sameDayReminder: Bool = false,
        pauseEpisodes: [PauseEpisode] = [],
        trial: TrialTerm? = nil,
        paymentMethodID: UUID? = nil,
        cancellationURL: URL? = nil,
        cancellationNotes: String? = nil,
        lastUsedDate: CalendarDay? = nil,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) -> (subscription: Subscription, repairs: [SubscriptionReadRepair]) {
        var repairs: [SubscriptionReadRepair] = []
        let episodes = repairingPauseEpisodes(
            pauseEpisodes, status: status, deletedAt: deletedAt, into: &repairs
        )
        if deletedAt == nil, status == .paused,
           !episodes.contains(where: { $0.endedOn == nil && $0.deletedAt == nil }) {
            repairs.append(.pausedWithoutOpenEpisode)
        }
        if status == .trial, trial == nil {
            repairs.append(.trialWithoutTerm)
        }
        let subscription = Subscription(
            unchecked: (), id: id, name: name, vendorURL: vendorURL, category: category,
            status: status, amountCents: amountCents, currencyCode: currencyCode, cycle: cycle,
            cycleStartDay: cycleStartDay, reminderLeadDays: reminderLeadDays,
            sameDayReminder: sameDayReminder, pauseEpisodes: episodes, trial: trial,
            paymentMethodID: paymentMethodID, cancellationURL: cancellationURL,
            cancellationNotes: cancellationNotes, lastUsedDate: lastUsedDate, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
        return (subscription, repairs)
    }

    /// The two episode repairs, in a fixed order so both devices converge:
    /// first at-most-one-open (earliest start wins, later ones closed at the
    /// winner's start, clamped so no closure precedes the loser's own start -
    /// §4a-2a), then no-open-beside-active/trial (the parent's status is
    /// authoritative; survivors close at their own start). `updatedAt` is
    /// left untouched - a repair is not a user statement, and stamping one
    /// would need a clock the domain does not read.
    private static func repairingPauseEpisodes(
        _ pauseEpisodes: [PauseEpisode],
        status: SubscriptionStatus,
        deletedAt: Date?,
        into repairs: inout [SubscriptionReadRepair]
    ) -> [PauseEpisode] {
        var episodes = pauseEpisodes
        let isOpen = { (episode: PauseEpisode) in episode.endedOn == nil && episode.deletedAt == nil }

        let open = episodes.filter(isOpen).sorted(by: startsEarlier)
        if let winner = open.first, open.count > 1 {
            for loser in open.dropFirst() {
                guard let index = episodes.firstIndex(where: { $0.id == loser.id }),
                      let candidate = winner.startedOn
                          ?? loser.startedOn ?? loser.scheduledResumeOn ?? winner.scheduledResumeOn
                          ?? utcDay(of: loser.createdAt)
                else { continue }
                // §4a-2a's clamp: the winner started first, so "closed at the
                // winner's start" would end this episode before its own start.
                // An episode closed at a point before its start is closed AT
                // its start - zero duration, honestly recording "recorded,
                // never actually in effect".
                episodes[index].endedOn = loser.startedOn.map { max(candidate, $0) } ?? candidate
                episodes[index].outcome = .superseded
                repairs.append(.extraOpenPauseEpisodeClosed(episodeID: loser.id))
            }
        }

        if deletedAt == nil, status == .active || status == .trial {
            for index in episodes.indices where isOpen(episodes[index]) {
                guard let closeDay = episodes[index].startedOn
                    ?? episodes[index].scheduledResumeOn ?? utcDay(of: episodes[index].createdAt)
                else { continue }
                episodes[index].endedOn = closeDay
                episodes[index].outcome = .superseded
                repairs.append(.conflictingOpenPauseEpisodeClosed(episodeID: episodes[index].id))
            }
        }
        return episodes
    }

    /// The "earliest start wins" order: `startedOn` ascending with nil first
    /// (a nil start is a pre-Wave-7 episode - older than any recorded start),
    /// then `createdAt`, then id, so the order is total and identical on
    /// every device.
    private static func startsEarlier(_ lhs: PauseEpisode, _ rhs: PauseEpisode) -> Bool {
        switch (lhs.startedOn, rhs.startedOn) {
        case (nil, .some): return true
        case (.some, nil): return false
        case (let left?, let right?) where left != right: return left < right
        default: return (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
        }
    }

    /// Last-resort close day for an episode with no calendar field at all (a
    /// doubly-degenerate pre-Wave-7 pair): the UTC day of its `createdAt`.
    /// A fixed calendar over a stored instant, not a clock read - both devices
    /// compute the same day. Nil only if the calendar produces impossible
    /// components, in which case the caller leaves the episode alone rather
    /// than inventing a date.
    private static func utcDay(of instant: Date) -> CalendarDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return CalendarDay(dateComponents: calendar.dateComponents([.year, .month, .day], from: instant))
    }
}
