import Testing
import OttoDomain

// Entry mode B (spec §5.1): most existing subscriptions have an unknowable start date,
// so the user enters the next charge date and the anchor is derived from it.
@Suite("Back-derivation of the anchor")
struct BackDerivationTests {

    @Test("derived anchor reproduces the entered next-billing-date", arguments: [
        BillingCycle.monthly, .quarterly, .annual, .weekly, .biweekly
    ])
    func roundTrip(cycle: BillingCycle) throws {
        let entered = try day(2026, 9, 15)
        let derivedAnchor = anchor(fromNextBillingDate: entered, cycle: cycle)
        let today = try day(2026, 8, 6)
        #expect(nextBillingDate(after: today, anchor: derivedAnchor, cycle: cycle) == entered)
    }

    @Test("a Feb 28 next-billing-date on a 31-anchored subscription round-trips")
    func feb28OnA31AnchoredSubscription() throws {
        // The vendor's true anchor is the 31st, but a Feb 28 next-charge date cannot
        // reveal that: Feb 28 is the clamped billing day for anchors 28, 29, 30, and 31
        // alike. The rule is to anchor at the entered date, which reproduces it exactly
        // and continues on the 28th - the only honest reading of the information entered.
        let entered = try day(2027, 2, 28)
        let derivedAnchor = anchor(fromNextBillingDate: entered, cycle: .monthly)

        let today = try day(2027, 2, 1)
        #expect(nextBillingDate(after: today, anchor: derivedAnchor, cycle: .monthly) == entered)

        let mar28 = try day(2027, 3, 28)
        #expect(billingDate(occurrence: 1, anchor: derivedAnchor, cycle: .monthly) == mar28)
    }
}
