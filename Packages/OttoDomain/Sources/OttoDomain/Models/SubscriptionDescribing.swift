import Foundation

extension Subscription {
    /// The §4a principle 2b WRITE construction (v2.1) - the edit path's
    /// constructor. Editing a degraded record must re-describe the degraded
    /// shape without trapping, but a write path must never borrow
    /// `readingRepaired`'s tolerance: its whole job is to never fail, so a
    /// future change to the repair rules would silently change write
    /// validation. Tolerance here is scoped to exactly the one degraded shape
    /// the edit form can legitimately hold - a live `.paused` with no open
    /// episode (the form carries pause history through untouched, and an
    /// edit's status preserves `.paused`; the missing episode is the
    /// incomplete aggregate still awaiting its record). Every other `init`
    /// invariant is enforced identically: the form always supplies a term
    /// with `.trial`, never reorders episodes, and never invents an open one,
    /// so any other degraded shape reaching here is a bug, not a description.
    /// (Parameter count mirrors `init` - the two must stay field-for-field.)
    public static func describing( // swiftlint:disable:this function_parameter_count
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
    ) -> Subscription {
        precondition(
            status != .trial || trial != nil,
            "A .trial subscription must have a TrialTerm (spec §5.2b)"
        )
        let openPauses = pauseEpisodes.count { $0.endedOn == nil && $0.deletedAt == nil }
        precondition(
            openPauses <= 1,
            "At most one pause episode can be current (spec §5.3a)"
        )
        // The one tolerated degradation: a live `.paused` may have NO open
        // episode - re-describing a parent whose episode record has not
        // arrived (spec §4a principle 2b). `init` requires exactly one.
        precondition(
            deletedAt != nil || openPauses == 0 || (status != .active && status != .trial),
            "An open PauseEpisode cannot coexist with a stored .active or .trial (spec §5.3a)"
        )
        return Subscription(
            unchecked: (), id: id, name: name, vendorURL: vendorURL, category: category,
            status: status, amountCents: amountCents, currencyCode: currencyCode, cycle: cycle,
            cycleStartDay: cycleStartDay, reminderLeadDays: reminderLeadDays,
            sameDayReminder: sameDayReminder, pauseEpisodes: pauseEpisodes, trial: trial,
            paymentMethodID: paymentMethodID, cancellationURL: cancellationURL,
            cancellationNotes: cancellationNotes, lastUsedDate: lastUsedDate, notes: notes,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}
