import Foundation
import OttoDomain

// The §6.2 reconciliation: the diff between what is pending and what is
// desired, and the logging that makes a pass legible afterwards. Split out of
// NotificationScheduler.swift, which passed SwiftLint's file_length AND
// type_body_length; the seam is the one Wave 10 already drew - everything here
// is about reconciling the notification centre against a plan that has already
// been decided.

extension NotificationScheduler {

    /// The diff (Wave 10, defect B): removes only identifiers the plan no
    /// longer wants, adds only identifiers the device does not already hold
    /// with identical content - `UNUserNotificationCenter` replaces on same
    /// identifier, so a changed spec is one idempotent add, and an unchanged
    /// one is no call at all. Removes go first only because they free budget
    /// slots; no desired rung is ever among them.
    ///
    /// The conversion announcement is never cancelled by a reschedule (Wave
    /// 10, defect C; spec §6.3): the escalation is a request and can be
    /// waived, the announcement is a fact and cannot. A pending announcement
    /// dated TODAY is structurally exempt from removal - if the desired plan
    /// would drop it (as the passed-hour filter did at 09:01 on conversion
    /// day, permanently cancelling the one notification that says money
    /// started moving), the device keeps it anyway. Past-dated announcements
    /// are removable: a day-late "converted today" is the dishonesty v1.4
    /// legislated against, and future-dated ones must go when a trial is
    /// cancelled before converting.
    func reconcile(
        desired specs: [NotificationRequestSpec],
        pending: [NotificationRequestSpec],
        today: CalendarDay
    ) async throws {
        let desiredByID = Dictionary(uniqueKeysWithValues: specs.map { ($0.identifier, $0) })
        let planned = pending.filter { !NotificationPlanIdentifier.isSnooze($0.identifier) }
        let stale = planned.filter { existing in
            desiredByID[existing.identifier] == nil && !isTodaysAnnouncement(existing, today: today)
        }
        if !stale.isEmpty {
            await client.removePendingRequests(withIdentifiers: stale.map(\.identifier))
        }
        let pendingByID = Dictionary(uniqueKeysWithValues: planned.map { ($0.identifier, $0) })
        // Every rung is ATTEMPTED before the pass gives up. Throwing from
        // inside the loop abandoned every spec ordered behind the first
        // refusal, deterministically, so the same rungs lost their slot on
        // every pass. The pass still reports failure afterwards - so Today
        // stops claiming coverage - but the device holds all it could take.
        var added: [String] = []
        var failures: [(id: String, error: any Error)] = []
        for spec in specs where pendingByID[spec.identifier] != spec {
            do { try await client.add(spec); added.append(spec.identifier) } catch {
                failures.append((spec.identifier, error))
            }
        }
        // The evidence that this is a diff and not the old remove-all: over an
        // unchanged plan both lists are empty while `pending` is not.
        // Identifiers, never counts - a count cannot tell a correct three-rung
        // replacement from a wipe.
        OttoLog.scheduling.notice("""
            reconcile pending=\(planned.count, privacy: .public) desired=\(specs.count, privacy: .public) \
            snoozesSpared=\(pending.count - planned.count, privacy: .public) \
            removed=[\(OttoLog.list(stale.map(\.identifier)), privacy: .public)] \
            added=[\(OttoLog.list(added), privacy: .public)] \
            failedCount=\(failures.count, privacy: .public)
            """)
        // The failures get one entry EACH, not one entry joining them all.
        //
        // `os_log` gives one entry a fixed ~1024-byte budget. Round 2 moved the
        // failure list off the diff line onto an aggregate entry of its own,
        // and that bought only the ~200 bytes the diff's other fields had been
        // spending: the joined list still pinned at ~1037 characters and named
        // 15-16 of 64 failed rungs at the device ceiling
        // (`reviews-4/REVIEW-AA92CA7.md`), and a truncated list reads as a
        // complete one. A rung that fails and is then not named is the exact
        // loss this is meant to repair, so each failure is named on its own
        // ~86-byte entry - the shape `OttoStore.watermarkDay` and the ledger
        // loop's SKIPPED lines already use - which no per-entry budget can
        // truncate at any scale the 64-slot ceiling allows. The aggregate entry
        // is gone rather than kept alongside: a knowingly-truncating list
        // masquerading as the record is the defect, and the diff line above
        // still carries `failedCount=` for the total. Identifiers, never
        // counts: the names live here.
        for failure in failures {
            OttoLog.scheduling.error("""
                reconcile failed \(OttoLog.failedRung(failure.id, failure.error), privacy: .public)
                """)
        }
        // After the log lines, so an investigation sees which rungs landed.
        //
        // Only the FIRST failure can be rethrown - the caller takes one error -
        // so the log is the only place the others can be recorded, and until it
        // carried `id=ErrorType` pairs they were collected and dropped.
        if let first = failures.first { throw first.error }
    }

    private func isTodaysAnnouncement(_ spec: NotificationRequestSpec, today: CalendarDay) -> Bool {
        NotificationPlanIdentifier.kind(of: spec.identifier) == .conversionAnnouncement
            && CalendarDay(year: spec.year, month: spec.month, day: spec.day) == today
    }
}
