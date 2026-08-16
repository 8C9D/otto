import Foundation

// Every merge rule in this app reads wall-clock stamps as causal order - §3.5's
// last-write-wins on `updatedAt`, §5.3's earliest-`createdAt` ledger merge - and
// a device clock the user can set is not a monotonic source. Real exported data
// already carries records whose `deletedAt` PRECEDES their `createdAt`, written
// under the advanced clock of this project's own verification procedure
// (docs/sync-safety.md). Clock manipulation cannot be prevented, so every write
// clamps instead of trusting the instant it is handed.

/// The stamp a write at `now` records: `now`, unless the record already carries
/// a later value the write may not move behind - the stamp it is replacing, or
/// the `createdAt` a tombstone cannot predate. A nil floor is a stored record
/// that never recorded one; there is nothing to hold the line at.
public func monotonicStamp(_ now: Date, notBefore floor: Date?) -> Date {
    guard let floor else { return now }
    return max(now, floor)
}
