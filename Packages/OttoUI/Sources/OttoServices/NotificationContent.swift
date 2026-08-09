import Foundation
import OttoDomain

/// The words each notification says - pure functions of the reminder and its
/// subscription, so the copy is testable and a reschedule reproduces it exactly.
enum NotificationContent {

    static func title(for reminder: PlannedReminder, subscription: Subscription) -> String {
        switch reminder.kind {
        case .renewal, .renewalDayOf:
            String(localized: "\(subscription.name) renews soon")
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily:
            String(localized: "\(subscription.name) trial deadline")
        case .conversionAnnouncement:
            String(localized: "\(subscription.name) trial converted")
        case .verification:
            String(localized: "Did \(subscription.name) really stop?")
        case .usageCheckIn:
            String(localized: "Still using \(subscription.name)?")
        case .pauseEnding:
            String(localized: "\(subscription.name) resumes billing")
        }
    }

    static func body(
        for reminder: PlannedReminder,
        subscription: Subscription,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let name = subscription.name
        switch reminder.kind {
        case .renewal:
            let amount = money(subscription.billingAmountCents(asOf: reminder.day), subscription.currencyCode, locale)
            let billing = reminder.day.adding(days: subscription.reminderLeadDays)
            return String(localized: "\(name) charges \(amount) on \(displayDate(billing, locale)).")
        case .renewalDayOf:
            let amount = money(subscription.billingAmountCents(asOf: reminder.day), subscription.currencyCode, locale)
            return String(localized: "\(name) charges \(amount) today.")
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily:
            return trialBody(kind: reminder.kind, subscription: subscription, locale: locale)
        case .conversionAnnouncement:
            // Not a request to act - a statement that money started moving
            // (spec §5.2a). The FoodApp sentence, verbatim in shape.
            let amount = subscription.trial.map { perCycle($0.convertsToAmountCents, subscription, locale) }
                ?? perCycle(subscription.amountCents, subscription, locale)
            return String(localized: "Your \(name) trial converted today. You're now being charged \(amount).")
        case .verification:
            return verificationBody(subscription: subscription, cancelledAt: nil, timeZone: nil, locale: locale)
        case .usageCheckIn:
            return String(localized: "Have you used \(name) lately? If not, it may be money moving for nothing.")
        case .pauseEnding:
            let amount = money(subscription.amountCents, subscription.currencyCode, locale)
            let resumes = subscription.pauseEndsOn.map { displayDate($0, locale) } ?? String(localized: "soon")
            return String(localized: "\(name) resumes billing \(resumes) at \(amount).")
        }
    }

    private static func trialBody(
        kind: PlannedReminder.Kind,
        subscription: Subscription,
        locale: Locale
    ) -> String {
        let name = subscription.name
        guard let trial = subscription.trial else {
            return String(localized: "The \(name) trial is near its deadline.")
        }
        let price = perCycle(trial.convertsToAmountCents, subscription, locale)
        let conversion = displayDate(trial.conversionDate, locale)
        switch kind {
        case .trialLead:
            let deadline = displayDate(trial.cancelByDate, locale)
            return String(localized: "Cancel \(name) by \(deadline) or it converts to \(price) on \(conversion).")
        case .trialDayOfMorning:
            return String(localized: "Today is the last safe day to cancel \(name). It converts to \(price) on \(conversion).")
        case .trialDayOfEvening:
            return String(localized: "Last call: cancel \(name) tonight or it converts to \(price).")
        default:
            return String(
                localized: "The \(name) cancel-by day has passed, but it hasn't converted yet. It converts to \(price) on \(conversion)."
            )
        }
    }

    /// The §6.3 verification check, with the cancellation date when the record is
    /// on hand: "You cancelled FoodApp on Aug 12. A charge was due today - check
    /// your statement. Did it stop?" The date is the one fact that anchors the
    /// question to the user's memory of actually cancelling.
    static func verificationBody(
        subscription: Subscription,
        cancelledAt: Date?,
        timeZone: TimeZone?,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let name = subscription.name
        guard let cancelledAt, let timeZone else {
            return String(
                localized: "You cancelled \(name). A charge was due today - check your statement. Did it stop?"
            )
        }
        let cancelled = cancelledAt.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
        )
        return String(
            localized: "You cancelled \(name) on \(cancelled). A charge was due today - check your statement. Did it stop?"
        )
    }

    /// "$11.00" - notification copy formats money exactly once, here.
    ///
    /// The locale is a parameter for the same reason `currencyText` in
    /// `DisplayFormatting` takes one: `.currency` renders CAD as "$11.00" in
    /// en_CA and "CA$11.00" in en_US, so a hard-coded expectation is really an
    /// assertion about the machine running the test. Defaulting to
    /// `.autoupdatingCurrent` keeps the app localized for whoever reads the
    /// notification; passing an explicit locale is what makes the copy testable.
    static func money(_ cents: Int, _ currencyCode: String, _ locale: Locale = .autoupdatingCurrent) -> String {
        let amount = Decimal(cents) / 100
        return amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    /// "$11.00/month" - the price with its cadence, because the cadence is the
    /// half of the number that makes it real.
    static func perCycle(
        _ cents: Int,
        _ subscription: Subscription,
        _ locale: Locale = .autoupdatingCurrent
    ) -> String {
        "\(money(cents, subscription.currencyCode, locale))\(cycleSuffix(subscription.cycle))"
    }

    private static func cycleSuffix(_ cycle: BillingCycle) -> String {
        switch (cycle.unit, cycle.interval) {
        case (.day, 1): String(localized: "/day")
        case (.week, 1): String(localized: "/week")
        case (.month, 1): String(localized: "/month")
        case (.year, 1): String(localized: "/year")
        case (.day, let count): String(localized: " every \(count) days")
        case (.week, let count): String(localized: " every \(count) weeks")
        case (.month, let count): String(localized: " every \(count) months")
        case (.year, let count): String(localized: " every \(count) years")
        }
    }

    /// Carries the locale for the same reason `money` does: `.month(.abbreviated)`
    /// is "Aug" in English and something else everywhere ambient locale can
    /// wander to.
    private static func displayDate(_ day: CalendarDay, _ locale: Locale = .autoupdatingCurrent) -> String {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = gregorian.date(from: components) else { return day.description }
        return date.formatted(
            Date.FormatStyle(locale: locale, timeZone: gregorian.timeZone).month(.abbreviated).day()
        )
    }
}

/// The notification categories and their action buttons (spec §6.4).
public enum NotificationCategory {
    /// Renewal and trial reminders carry the three §6.4 actions.
    public static let actionable = "otto.category.reminder"
    /// Verification checks carry the yes/no answer buttons (spec §5.4, Wave 5).
    public static let verification = "otto.category.verification"
    /// Usage check-ins carry the §7.3 responses (Wave 7): "still using it"
    /// records the use in the background; "not really" opens the subscription
    /// so the user can decide - Otto presents facts, never a recommendation.
    public static let usage = "otto.category.usage"
    /// Everything else is informational.
    public static let plain = ""

    public static func identifier(for kind: PlannedReminder.Kind) -> String {
        switch kind {
        case .renewal, .renewalDayOf, .trialLead, .trialDayOfMorning,
             .trialDayOfEvening, .trialDaily:
            actionable
        case .verification:
            verification
        case .usageCheckIn:
            usage
        case .conversionAnnouncement, .pauseEnding:
            plain
        }
    }
}

/// The action buttons (spec §6.4 and, since Wave 5, the §5.4 verification
/// answers), by stable identifier.
public enum NotificationAction: String, CaseIterable, Sendable {
    case keepingIt = "otto.action.keepingIt"
    case cancelling = "otto.action.cancelling"
    case remindLater = "otto.action.remindLater"
    /// Verification yes-path: the charge stopped - verify and archive, all in
    /// the background.
    case chargesStopped = "otto.action.chargesStopped"
    /// Verification no-path: a charge arrived - record it and bring the dispute
    /// summary to the screen (foreground-registered).
    case stillCharging = "otto.action.stillCharging"
    /// Usage check-in yes-path (spec §7.3): records today as the last use, all
    /// in the background - answering must work with the phone in a pocket.
    case stillUsing = "otto.action.stillUsing"
    /// Usage check-in other-path: opens the subscription. What to do about an
    /// unused subscription is the user's decision, so the button leads to the
    /// facts rather than performing anything.
    case notUsing = "otto.action.notUsing"
}
