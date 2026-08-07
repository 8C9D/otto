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

    static func body(for reminder: PlannedReminder, subscription: Subscription) -> String {
        let name = subscription.name
        switch reminder.kind {
        case .renewal:
            let amount = money(subscription.billingAmountCents(asOf: reminder.day), subscription.currencyCode)
            let billing = reminder.day.adding(days: subscription.reminderLeadDays)
            return String(localized: "\(name) charges \(amount) on \(displayDate(billing)).")
        case .renewalDayOf:
            let amount = money(subscription.billingAmountCents(asOf: reminder.day), subscription.currencyCode)
            return String(localized: "\(name) charges \(amount) today.")
        case .trialLead, .trialDayOfMorning, .trialDayOfEvening, .trialDaily:
            return trialBody(kind: reminder.kind, subscription: subscription)
        case .conversionAnnouncement:
            // Not a request to act - a statement that money started moving
            // (spec §5.2a). The FoodApp sentence, verbatim in shape.
            let amount = subscription.trial.map { perCycle($0.convertsToAmountCents, subscription) }
                ?? perCycle(subscription.amountCents, subscription)
            return String(localized: "Your \(name) trial converted today. You're now being charged \(amount).")
        case .verification:
            return String(
                localized: "You cancelled \(name). A charge was due today - check your statement. Did it stop?"
            )
        case .usageCheckIn:
            return String(localized: "Have you used \(name) lately? If not, it may be money moving for nothing.")
        case .pauseEnding:
            let amount = money(subscription.amountCents, subscription.currencyCode)
            let resumes = subscription.pauseEndsOn.map(displayDate) ?? String(localized: "soon")
            return String(localized: "\(name) resumes billing \(resumes) at \(amount).")
        }
    }

    private static func trialBody(kind: PlannedReminder.Kind, subscription: Subscription) -> String {
        let name = subscription.name
        guard let trial = subscription.trial else {
            return String(localized: "The \(name) trial is near its deadline.")
        }
        let price = perCycle(trial.convertsToAmountCents, subscription)
        let conversion = displayDate(trial.conversionDate)
        switch kind {
        case .trialLead:
            let deadline = displayDate(trial.cancelByDate)
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

    /// "$11.00" - notification copy formats money exactly once, here.
    static func money(_ cents: Int, _ currencyCode: String) -> String {
        let amount = Decimal(cents) / 100
        return amount.formatted(.currency(code: currencyCode))
    }

    /// "$11.00/month" - the price with its cadence, because the cadence is the
    /// half of the number that makes it real.
    static func perCycle(_ cents: Int, _ subscription: Subscription) -> String {
        "\(money(cents, subscription.currencyCode))\(cycleSuffix(subscription.cycle))"
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

    private static func displayDate(_ day: CalendarDay) -> String {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = gregorian.date(from: components) else { return day.description }
        return date.formatted(
            Date.FormatStyle(timeZone: gregorian.timeZone).month(.abbreviated).day()
        )
    }
}
