import Foundation
import OSLog
import OttoDomain

/// Otto's unified-log channels.
///
/// The app is judged almost entirely on what it does while nobody is watching:
/// a background pass that misfires leaves no screen to inspect afterwards, and
/// the Aug 2026 trial gate was settled by a device log archive after a static
/// trace had backed the wrong hypothesis. So the background and scheduling
/// paths write to the unified log, where `log collect --device` can pull them
/// off the phone days later.
///
/// **Privacy.** This is a financial app and a sysdiagnose is readable by anyone
/// holding the device. Nothing here logs an amount, a vendor name, a payment
/// method, or any other subscription content. What is marked `.public` is
/// deliberately limited to opaque identifiers (`<uuid>|<day>|<kind>`),
/// calendar days, and control-flow outcomes - the facts an investigation needs,
/// none of which say what the user pays for. Anything richer must stay out, not
/// merely be marked private: `.private` redaction is a display rule, not a
/// guarantee about what was written.
public enum OttoLog {
    public static let subsystem = "com.arthurzhang.otto"

    /// `BGAppRefreshTask` lifecycle: launch, which completion path was taken,
    /// and whether the next wake-up was re-armed.
    public static let background = Logger(subsystem: subsystem, category: "background")

    /// Reschedule passes: which trigger started one, the §6.2 reconciliation
    /// diff it produced, and what the ledger watermarks did across it.
    public static let scheduling = Logger(subsystem: subsystem, category: "scheduling")

    /// Notification actions (spec §6.4): what the user answered from the lock
    /// screen, and whether the state work behind it succeeded.
    ///
    /// This is the one boundary where a failure is completely unobservable
    /// otherwise. The delegate discards the handler's error, the system has
    /// already consumed the notification, and the user has watched their answer
    /// disappear into a banner - "Keeping it", "Yes - it stopped", "still using
    /// it" and a snooze all look identical whether they were recorded or
    /// thrown away. An acknowledgement that did not persist re-warns later and
    /// is at least visible; a snooze that threw is the reminder simply ceasing
    /// to exist.
    ///
    /// Same privacy rule as the rest of this file: the notification identifier
    /// is the opaque `<uuid>|<day>|<kind>` triple and the action identifier is
    /// a fixed constant, so neither says what the user pays for.
    public static let actions = Logger(subsystem: subsystem, category: "actions")

    /// Import and export (spec §3.5, F11): which direction, which strategy,
    /// how many records, and whether it finished.
    ///
    /// This is the recovery path, and it was completely silent: after a restore
    /// that went wrong while nobody was watching, the device held no record that
    /// a restore had even been attempted. Gate 3 was settled by counting rows in
    /// a copied container, because there was nothing else to read.
    ///
    /// Counts and outcomes only. A file NAME is never logged - an export lands
    /// under a dated Otto filename but an import is whatever the user picked,
    /// and a path can carry their name or a vendor's.
    public static let dataTransfer = Logger(subsystem: subsystem, category: "transfer")

    /// The §5.4 cancellation and verification lifecycle (F11).
    ///
    /// The other boundary round 1 named and nothing recorded. A cancellation
    /// that failed to open its episode, a verification that archived the
    /// subscription, an un-cancel that restored it - all of them changed money
    /// state and left the same silence behind. Opaque identifiers and
    /// control-flow outcomes, like everything else here: never the vendor, the
    /// amount, or the evidence note the user typed.
    public static let flows = Logger(subsystem: subsystem, category: "flows")

    /// A `CalendarDay?` as log text - "none" reads better than an empty slot
    /// when the question being asked is whether a watermark exists at all.
    static func dayText(_ day: CalendarDay?) -> String {
        day.map(String.init(describing:)) ?? "none"
    }

    /// Identifier lists are logged in full rather than counted: the whole point
    /// of the §6.2 diff is WHICH rungs moved, and a count cannot distinguish a
    /// correct three-rung replacement from a remove-all.
    static func list(_ identifiers: [String]) -> String {
        identifiers.isEmpty ? "-" : identifiers.sorted().joined(separator: " ")
    }

    /// The `pass end` line's fields, as a value.
    ///
    /// **R4-3.** `ScheduleOutcome.truncatedAfter` reached nothing at all: the
    /// scheduler set it, `coveredThrough` was computed from the same local, and
    /// no reader anywhere - production or UI - ever asked the outcome for it.
    /// This line carried every OTHER field of the outcome and not that one, so a
    /// pass that dropped rungs past the budget and a pass that dropped none
    /// logged identically whenever their `coveredThrough` agreed, which is
    /// exactly when the distinction matters.
    ///
    /// Composed here rather than interpolated at the call site so a test can
    /// read the line without opening `OSLogStore`. That is a convenience and
    /// NOT the guard: `reviews-4/REVIEW-5.md` measured that restoring the
    /// pre-fix interpolation left this function correct, its unit test green
    /// and all 209 host tests passing, so R4-3 was fully restorable behind it.
    /// The emission is guarded in `SchedulingLogTests`, inside a query that
    /// suite already opens - at zero additional `OSLogStore` reads, which is
    /// what an earlier version of this comment wrongly said the fix would cost.
    ///
    /// Every field is an opaque count, a control-flow outcome or a calendar
    /// day, which is what `.public` on the whole string is allowed to mean.
    static func passEndFields(trigger: RescheduleTrigger, outcome: ScheduleOutcome) -> String {
        """
        pass end trigger=\(trigger.rawValue) \
        permission=\(String(describing: outcome.permission)) \
        scheduled=\(outcome.scheduledCount) \
        coveredThrough=\(String(describing: outcome.coveredThrough)) \
        truncatedAfter=\(dayText(outcome.truncatedAfter)) \
        ledgerFailures=\(outcome.ledgerFailures.count)
        """
    }

    /// One failed rung as an `identifier=ErrorType` pair.
    ///
    /// The reason, not just the identifier. `reconcile` attempts every rung and
    /// collects every failure, but it can rethrow only one, so an entry naming
    /// bare identifiers left the reasons for failures 2..n reaching neither the
    /// log nor the caller. On a device where two causes coexist - the 64-slot
    /// ceiling refusing one rung and something else refusing another - an
    /// investigation saw one error type and a list of names, and could not tell
    /// that a second cause existed at all.
    ///
    /// One PAIR, never a joined list (this replaced `failures(_:)`, which
    /// joined them): the joined form re-entered `os_log`'s ~1024-byte per-entry
    /// budget and named 15-16 of 64 failed rungs at the device ceiling - N2-4,
    /// reopened by `reviews-4/REVIEW-AA92CA7.md`. Each rung now gets a log
    /// entry of its own at the reconcile call site.
    ///
    /// The TYPE only, never the value, which is the rule
    /// `NotificationActionHandler`'s failure line already follows: an error can
    /// carry a payload, and this file's privacy rule is that nothing richer
    /// than a control-flow outcome goes to the log.
    static func failedRung(_ id: String, _ error: any Error) -> String {
        "\(id)=\(String(describing: type(of: error)))"
    }
}

/// Which §6.2 trigger started a scheduling pass. Logged so a later
/// investigation can tell a background wake-up from a foreground open without
/// inferring it from timestamps - the distinction the `BGAppRefreshTask` gate
/// exists to observe.
public enum RescheduleTrigger: String, Sendable {
    case foreground
    case backgroundRefresh
    case notificationDelivered
    case notificationAction
    case timeZoneChange
    case significantTimeChange
    /// A create, edit, delete, or notification-time change routed through the
    /// store layer.
    case stateChange
}

extension ReminderScheduling {

    /// The trigger-tagged entry point every production caller uses.
    ///
    /// The protocol requirement deliberately keeps its three parameters: Swift
    /// forbids default arguments in a protocol requirement, so widening it
    /// would rewrite ~70 test call sites to carry a value only the log reads.
    /// Tagging here instead puts the trigger name immediately before the pass
    /// it names, in the same log stream, at no cost to the seam.
    @discardableResult
    public func reschedule(
        now: Date,
        today: CalendarDay,
        timeZone: TimeZone,
        trigger: RescheduleTrigger
    ) async throws -> ScheduleOutcome {
        OttoLog.scheduling.notice("pass begin trigger=\(trigger.rawValue, privacy: .public)")
        do {
            let outcome = try await reschedule(now: now, today: today, timeZone: timeZone)
            OttoLog.scheduling.notice(
                "\(OttoLog.passEndFields(trigger: trigger, outcome: outcome), privacy: .public)"
            )
            return outcome
        } catch {
            OttoLog.scheduling.error("""
                pass threw trigger=\(trigger.rawValue, privacy: .public) \
                error=\(String(describing: type(of: error)), privacy: .public)
                """)
            throw error
        }
    }
}
