// The coverage-gap card, split out of TodayView.swift when item 9's copy
// matrix pushed that file past SwiftLint's 400-line file_length - the same
// seam TodaySectionPlan.swift drew: this type is self-contained, holds the one
// wording rule its tests pin, and TodayView only constructs it.
import SwiftUI
import OttoStores

/// One Today card: what it is, why it is here, and when.
/// The coverage sentence's counterpart, in the aggregate-card shape
/// `unreadableRecordsSection` established: say that reminders could not be
/// updated, and how many subscriptions it touched.
///
/// A count and nothing else. Naming the vendors would put subscription content
/// on a screen readable at a glance, and the user does not need it to know
/// something is wrong - `ledgerFailures` carries only UUIDs anyway.
///
/// Its own `View` rather than a method on `TodayView`, following `TodayEntryRow`:
/// a private `@ViewBuilder` that reads `model` cannot be rendered by a test, and
/// this card is new copy that has to be seen to be believed.
struct CoverageGapCard: View {
    /// Zero when the whole pass failed, so there is no per-subscription count to
    /// give - a different sentence, because "0 subscriptions couldn't be
    /// updated" is not what happened.
    let failureCount: Int
    /// How many of `failureCount` are deliberate implausible-day silencings
    /// (round 5, item 9 / N3-5). The transient copy was FALSE for them:
    /// "couldn't refresh... it will try again" described a subscription Otto
    /// stopped on purpose, one that stays silent until the user fixes its
    /// dates - so waiting, which the copy recommended, is exactly wrong.
    /// Defaults to zero so the transient-only construction reads as before.
    var implausibleCount: Int = 0

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }

    /// Not private, for the same reason `InsightsView.monthText` is not: the
    /// choice BETWEEN the wordings needs no accessibility tree to assert,
    /// and while it was private they could be swapped - rendering "0
    /// subscriptions couldn't be updated" for a whole failed pass, or the
    /// transient copy for a deliberate silencing - with every test on both
    /// the host and the simulator green.
    ///
    /// The copy matrix (round 5, item 9, the user's approved wording,
    /// verbatim): corrupt-only passes get the unusable-dates copy; transient
    /// failures keep the existing copy; a mixed pass keeps the transient copy
    /// and appends the corruption sentences, because those are the actionable
    /// half. The surrounding copy is number-invariant by design - the
    /// inflection engine does not conjugate verbs.
    var headline: String {
        if failureCount > 0 && implausibleCount == failureCount {
            return String(localized: "\(subscriptionCountText(implausibleCount)) with unusable dates")
        }
        return failureCount > 0
            ? String(localized: "\(subscriptionCountText(failureCount)) couldn't be updated")
            : String(localized: "Reminders couldn't be updated")
    }

    var detail: String {
        guard failureCount > 0 else {
            return String(localized: """
              Otto's last check didn't finish, so some reminders may be missing. \
              Nothing was deleted, and it will try again.
              """)
        }
        if implausibleCount == failureCount {
            return String(localized: """
              Their stored dates aren't real calendar days, so Otto has stopped their reminders \
              on purpose. Nothing was deleted. Open each subscription and fix its dates - \
              reminders resume automatically once every date is fixed.
              """)
        }
        let transient = String(localized: """
          Otto couldn't refresh their reminders on its last check, so some may be missing. \
          Nothing was deleted, and it will try again.
          """)
        guard implausibleCount > 0 else { return transient }
        // The mixed pass: the transient copy stays for the genuine failures,
        // and the corruption sentences follow because they are the actionable
        // half. "Nothing was deleted." is not repeated - the transient copy
        // already says it - and every sentence here is the approved copy.
        return transient + " " + String(localized: """
          Their stored dates aren't real calendar days, so Otto has stopped their reminders \
          on purpose. Open each subscription and fix its dates - reminders resume \
          automatically once every date is fixed.
          """)
    }
}
