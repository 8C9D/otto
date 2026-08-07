import Foundation

/// One pause in a subscription's life (spec §5.3a) - a one-to-many history row,
/// because pausing recurs: a gym frozen every winter is ordinary life, not error
/// correction, and the single pair of fields v1.7 stored could only remember the
/// latest pause by erasing the ones before it.
///
/// Nothing is ever cleared on exit from a pause: exiting writes `endedOn` and an
/// outcome. The current pause is the episode with no end date; closed episodes
/// are what make "what did this cost me last year" answerable at all.
public struct PauseEpisode: Identifiable, Hashable, Sendable {

    /// How a closed episode ended. New cases are cheap (spec §5.6's raw-string
    /// rule); today there is exactly one exit, the resume. An episode open when
    /// its subscription archives stays open deliberately - billing never
    /// resumed, so writing a resume would be fiction (spec §5.3a).
    public enum Outcome: String, Codable, Hashable, Sendable, CaseIterable {
        /// Billing resumed - manually, or a derived resume persisted later.
        case resumed
    }

    /// Client-generated (spec §5.0): a record with no id of its own cannot be
    /// addressed individually by sync.
    public let id: UUID

    /// The day the pause began - the freeze point for §7.2's paused-spend price.
    /// Nil only on episodes migrated from records paused before Wave 7 recorded
    /// starts: no honest value exists for those, and Insights falls back to the
    /// current price (spec §5.1). A new episode always carries its start.
    public var startedOn: CalendarDay?

    /// When the vendor said billing resumes; drives the resume reminder and the
    /// §5.2a derived resume. Nil is an indefinite pause, which freezes the
    /// materialization watermark instead (spec §5.3).
    public var scheduledResumeOn: CalendarDay?

    /// The day the pause actually ended. Nil while the episode is current
    /// (spec §5.3a: the current episode is the one with no end date).
    public var endedOn: CalendarDay?

    /// Why it ended. Paired with `endedOn` by construction: an episode is either
    /// open (neither set) or closed (both set).
    public var outcome: Outcome?

    /// Audit instants (spec §5.0), injected by callers - the domain never reads a clock.
    public var createdAt: Date
    public var updatedAt: Date

    /// Soft-delete tombstone: a hard delete cannot be synced (spec §3.5).
    public var deletedAt: Date?

    public init(
        id: UUID,
        startedOn: CalendarDay?,
        scheduledResumeOn: CalendarDay? = nil,
        endedOn: CalendarDay? = nil,
        outcome: Outcome? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        precondition(
            (endedOn == nil) == (outcome == nil),
            "A PauseEpisode is open (no end, no outcome) or closed (both) - never half (spec §5.3a)"
        )
        self.id = id
        self.startedOn = startedOn
        self.scheduledResumeOn = scheduledResumeOn
        self.endedOn = endedOn
        self.outcome = outcome
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Current, in §5.3a's sense. Deleted episodes are tombstoned history and
    /// never current; callers filter those where it matters.
    public var isOpen: Bool { endedOn == nil }

    /// The episode closed by a resume (spec §5.3a: exiting writes an end date).
    /// A pause that ran past its scheduled resume ended THEN - the vendor
    /// resumed billing on that day whether or not anyone opened the app - so a
    /// later persisted resume records the scheduled day, not the tap's day.
    /// Nil when already closed.
    public func resuming(on today: CalendarDay, at now: Date) -> PauseEpisode? {
        guard isOpen else { return nil }
        var updated = self
        if let scheduled = scheduledResumeOn, scheduled <= today {
            updated.endedOn = scheduled
        } else {
            updated.endedOn = today
        }
        updated.outcome = .resumed
        updated.updatedAt = now
        return updated
    }
}

// MARK: - Codable

extension PauseEpisode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, startedOn, scheduledResumeOn, endedOn, outcome
        case createdAt, updatedAt, deletedAt
    }

    // Hand-written so decoding routes through the open-or-closed invariant
    // instead of assigning stored properties directly.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let endedOn = try container.decodeIfPresent(CalendarDay.self, forKey: .endedOn)
        let outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome)
        guard (endedOn == nil) == (outcome == nil) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A PauseEpisode is open (no end, no outcome) or closed (both) - never half (spec §5.3a)"
            ))
        }
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            startedOn: try container.decodeIfPresent(CalendarDay.self, forKey: .startedOn),
            scheduledResumeOn: try container.decodeIfPresent(CalendarDay.self, forKey: .scheduledResumeOn),
            endedOn: endedOn,
            outcome: outcome,
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(startedOn, forKey: .startedOn)
        try container.encodeIfPresent(scheduledResumeOn, forKey: .scheduledResumeOn)
        try container.encodeIfPresent(endedOn, forKey: .endedOn)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

// MARK: - The subscription's pause history (spec §5.3a)

extension Subscription {
    /// The pause this subscription is currently in - §5.3a's "the episode with
    /// no end date" - or nil when it is not in one. Tombstoned episodes are
    /// history, never current.
    public var currentPauseEpisode: PauseEpisode? {
        pauseEpisodes.first { $0.endedOn == nil && $0.deletedAt == nil }
    }

    /// The day the current pause began - v1.7's stored field, now derived from
    /// the open episode so the two can never disagree. Nil when not paused, and
    /// nil on a pause migrated from a record that never recorded its start;
    /// Insights falls back to the current price for those (spec §5.1).
    public var pausedOn: CalendarDay? { currentPauseEpisode?.startedOn }

    /// When the current pause is scheduled to end - v1.7's stored field, now
    /// derived from the open episode. Drives the resume reminder and the §5.2a
    /// derived resume; nil while not paused, or paused indefinitely.
    public var pauseEndsOn: CalendarDay? { currentPauseEpisode?.scheduledResumeOn }

    /// The construction preconditions on pause episodes, as a throwing check for
    /// the layers that must refuse bad data loudly instead of trapping on it -
    /// the persistence mapping and the export wire format, exactly like the
    /// §5.2b trial invariant. `makeError` wraps the violation in the caller's
    /// own error type.
    ///
    /// The status-coupled halves apply to LIVE records only (`deletedAt` nil):
    /// deleting a paused subscription tombstones its episodes with it, and
    /// that tombstoned whole is valid history a backup must still carry.
    public static func checkPauseInvariants(
        status: SubscriptionStatus,
        pauseEpisodes: [PauseEpisode],
        deletedAt: Date?,
        makeError: (String) -> any Error
    ) throws {
        let openPauses = pauseEpisodes.count { $0.endedOn == nil && $0.deletedAt == nil }
        if openPauses > 1 {
            throw makeError("at most one pause episode can be current (spec §5.3a)")
        }
        guard deletedAt == nil else { return }
        if status == .paused && openPauses == 0 {
            throw makeError("a .paused subscription must have an open PauseEpisode (spec §5.3a)")
        }
        if openPauses == 1 && (status == .active || status == .trial) {
            throw makeError("an open PauseEpisode cannot coexist with a stored .active or .trial (spec §5.3a)")
        }
    }
}
