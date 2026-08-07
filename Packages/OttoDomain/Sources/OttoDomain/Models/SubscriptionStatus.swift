/// The lifecycle state of a subscription (spec §5.1).
///
/// `paused` is first-class, not a flavour of `cancelled`: a paused subscription
/// generates no billing events and no renewal reminders, is excluded from monthly burn
/// but reported as its own line, and its `pauseEndsOn` date drives a resume reminder
/// so billing cannot silently restart unwatched.
///
/// `cancelled` is not terminal: a cancelled subscription stays under verification
/// until its `CancellationEpisode` confirms the charges actually stopped (spec §5.4);
/// only then does it become `archived`.
///
/// Raw values are stable strings, never ordinals, so reordering cases can never
/// corrupt stored data (spec §5.6).
public enum SubscriptionStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case trial
    case active
    case paused
    case cancellationPending
    case cancelled
    case archived
}
