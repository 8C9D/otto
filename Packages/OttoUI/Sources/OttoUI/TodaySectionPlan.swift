// The sections Today's list composes, and the rule that decides which of them
// appear. Split out of TodayView.swift because that file passed SwiftLint's
// 400-line file_length limit; the seam is the one this type already documents -
// it is the pure composition decision, it holds no view, and it is what
// TodaySectionPlanTests exercises.
import SwiftUI
import OttoDomain
import OttoServices
import OttoStores

/// The sections Today's list composes, in render order - extracted from the
/// view builder because Wave 9A defect 1 lived exactly there: the empty-database
/// branch returned a bare placeholder and silently dropped the permission
/// surface, a decision no store-level test could see.
enum TodaySection: Hashable {
    /// §6 constraint 3's surface: the denied banner, the not-yet-asked request
    /// button, or the provisional note. Present for EVERY database state,
    /// including an empty one - a first-launch user with nothing entered yet
    /// must be able to reach the permission request from Today.
    case notificationStatus
    case unreadableRecords
    case readRepairs
    /// Spec §7.1's empty state, INSIDE the list so the surfaces above survive.
    case noSubscriptionsYet
    case needsAction
    case next30Days
    case later
    /// The horizon, stated honestly (spec §6.1 point 4).
    case coverage
    /// The other half of stating the horizon honestly: coverage was NOT earned
    /// this pass. Withdrawing the coverage sentence (F3, R0-1) stopped Today
    /// overstating, but `.notificationStatus` renders only for a permission
    /// other than authorized - so an authorized user whose engine has failed on
    /// every pass since install saw no notification surface at all, which on an
    /// app whose characteristic failure is silence is the wrong resting place.
    case coverageGap

    /// Everything the composition depends on, in one value - so the test can
    /// state a whole screen state in one place.
    struct Input {
        var subscriptionsEmpty = false
        /// Nil when no notification engine exists at all.
        var permission: NotificationPermission?
        var unreadableCount = 0
        var hasReadRepairs = false
        var hasNext30Days = false
        var hasLater = false
        /// The latest pass's outcome, or nil when no pass has succeeded since
        /// the last failure. Whether it may be STATED is decided in `plan`,
        /// not by the caller - the mapping from an outcome to a coverage claim
        /// is the rule this type exists to pin, and computing it at the call
        /// site put it in a SwiftUI body where no test can reach it.
        var scheduleOutcome: ScheduleOutcome?
        /// Whether the LAST pass failed outright, as opposed to no pass having
        /// run yet. Both leave `scheduleOutcome` nil, and only the first is
        /// worth telling the user about - saying "reminders couldn't be
        /// updated" before the first pass has finished would be a false alarm
        /// on every launch.
        var lastPassFailed = false
    }

    /// The whole mapping, from the model the view holds.
    ///
    /// The view passes `model` and nothing else on purpose. When it picked the
    /// fields itself, `notifications: model.notifications` could be replaced
    /// with `nil` - deleting the permission banner, the coverage sentence and
    /// the coverage-gap card in one token - and every test stayed green,
    /// because what a `View` hands to a function is not reachable from a test.
    /// Each extraction that stops short of the arguments just moves that hole
    /// one frame out.
    @MainActor
    static func input(
        model: AppModel,
        overview: TodayOverview,
        subscriptionsEmpty: Bool
    ) -> Input {
        input(
            overview: overview,
            subscriptionsEmpty: subscriptionsEmpty,
            unreadableCount: model.subscriptionsStore.unreadableCount,
            hasReadRepairs: !model.subscriptionsStore.readRepairs.isEmpty,
            notifications: model.notifications
        )
    }

    /// The same mapping taken apart, for tests that vary one input at a time -
    /// including the absent-engine case, which a real `AppModel` cannot express
    /// without building a second one.
    ///
    /// NOT the seam the view uses. `TodaySection.Input` was extracted so the
    /// composition RULE would be testable, and that left the mapping behind in
    /// a private method on a `View` - the one shape no host test can reach, and
    /// Wave 9A defect 1's shape exactly. Round 1's R0-1 had it at this same
    /// call site.
    @MainActor
    static func input(
        overview: TodayOverview,
        subscriptionsEmpty: Bool,
        unreadableCount: Int,
        hasReadRepairs: Bool,
        notifications: NotificationStatusStore?
    ) -> Input {
        Input(
            subscriptionsEmpty: subscriptionsEmpty,
            permission: notifications?.permission,
            unreadableCount: unreadableCount,
            hasReadRepairs: hasReadRepairs,
            hasNext30Days: !overview.next30Days.isEmpty,
            hasLater: !overview.later.isEmpty,
            scheduleOutcome: notifications?.outcome,
            lastPassFailed: notifications?.lastPassFailed ?? false
        )
    }

    static func plan(_ input: Input) -> [TodaySection] {
        var sections: [TodaySection] = []
        if let permission = input.permission, permission != .authorized {
            sections.append(.notificationStatus)
        }
        if input.unreadableCount > 0 {
            sections.append(.unreadableRecords)
        }
        if input.hasReadRepairs {
            sections.append(.readRepairs)
        }
        guard !input.subscriptionsEmpty else {
            sections.append(.noSubscriptionsYet)
            return sections
        }
        sections.append(.needsAction)
        if input.hasNext30Days {
            sections.append(.next30Days)
        }
        if input.hasLater {
            sections.append(.later)
        }
        if input.permission == .authorized || input.permission == .provisional {
            if input.scheduleOutcome?.canClaimCoverage == true {
                sections.append(.coverage)
            } else if input.lastPassFailed || input.scheduleOutcome?.canClaimCoverage == false {
                // A pass that failed outright, or one that returned normally
                // while some subscriptions' ledgers threw. Either way the
                // horizon cannot be claimed, and saying nothing leaves this
                // screen indistinguishable from a healthy one.
                sections.append(.coverageGap)
            }
        }
        return sections
    }
}
