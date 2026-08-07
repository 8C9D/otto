import Foundation
import Testing
import OttoDomain
@testable import OttoStores

@MainActor
@Suite("Add/Edit form model (spec §5.1)")
struct SubscriptionFormModelTests {

    private func makeForm() throws -> SubscriptionFormModel {
        let form = SubscriptionFormModel(dates: try fixedDates())
        form.name = "Netflix"
        form.amount = Decimal(string: "10.99")
        return form
    }

    // MARK: - The two entry modes

    @Test("both entry modes store anchors that generate the same billing sequence")
    func modesAgree() throws {
        // The same real subscription - bills the 15th monthly - entered both ways.
        let modeA = try makeForm()
        modeA.entryMode = .startDate
        modeA.startDate = try day(2026, 1, 15)

        let modeB = try makeForm()
        modeB.entryMode = .nextCharge
        modeB.nextChargeDate = try day(2026, 8, 15)

        let subA = try #require(modeA.buildSubscription())
        let subB = try #require(modeB.buildSubscription())

        // The anchors are different occurrences of one sequence, so the day of
        // month agrees and every future billing date agrees.
        #expect(subA.anchorDay == subB.anchorDay)
        var checkFrom = try day(2026, 8, 6)
        for _ in 0..<6 {
            let nextA = nextBillingDate(after: checkFrom, anchor: subA.cycleStartDay, cycle: subA.cycle)
            let nextB = nextBillingDate(after: checkFrom, anchor: subB.cycleStartDay, cycle: subB.cycle)
            #expect(nextA == nextB)
            checkFrom = nextA
        }
    }

    @Test("mode A shows the computed next billing date live, including an anchor still ahead")
    func modeALiveConfirmation() throws {
        let form = try makeForm()
        form.entryMode = .startDate
        form.startDate = try day(2026, 1, 31)
        // Today is Aug 6: a Jan 31 monthly anchor bills Aug 31 next.
        #expect(form.computedNextBillingDate == (try day(2026, 8, 31)))

        form.startDate = try day(2026, 9, 15)
        // An anchor still ahead is itself the next billing date.
        #expect(form.computedNextBillingDate == (try day(2026, 9, 15)))
    }

    // MARK: - Mode B last-day disambiguation

    @Test("the last-day question appears exactly when the entered date is ambiguous")
    func questionAppears() throws {
        let form = try makeForm()
        form.entryMode = .nextCharge

        form.nextChargeDate = try day(2026, 8, 15)
        #expect(!form.needsLastDayAnswer)

        form.nextChargeDate = try day(2026, 9, 30)
        #expect(form.needsLastDayAnswer)
        #expect(form.canSave == false)
    }

    @Test("answering last-day-of-month anchors the 31st; answering the entered day anchors the 30th")
    func answersResolveAnchors() throws {
        let form = try makeForm()
        form.entryMode = .nextCharge
        form.nextChargeDate = try day(2026, 9, 30)

        form.lastDayAnswer = .lastDayOfMonth
        let lastDay = try #require(form.buildSubscription())
        #expect(lastDay.cycleStartDay == (try day(2026, 8, 31)))
        #expect(lastDay.anchorDay == 31)

        form.lastDayAnswer = .enteredDay
        let enteredDay = try #require(form.buildSubscription())
        #expect(enteredDay.cycleStartDay == (try day(2026, 9, 30)))
        #expect(enteredDay.anchorDay == 30)
    }

    @Test("the Feb 28 case resolves to 31 vs 28 - the spec's own example")
    func februaryCase() throws {
        let form = try makeForm()
        form.entryMode = .nextCharge
        form.nextChargeDate = try day(2027, 2, 28)
        #expect(form.needsLastDayAnswer)

        form.lastDayAnswer = .lastDayOfMonth
        #expect(try #require(form.buildSubscription()).anchorDay == 31)

        form.lastDayAnswer = .enteredDay
        #expect(try #require(form.buildSubscription()).anchorDay == 28)
    }

    @Test("changing the entered date or cycle clears a stale answer")
    func staleAnswerCleared() throws {
        let form = try makeForm()
        form.entryMode = .nextCharge
        form.nextChargeDate = try day(2026, 9, 30)
        form.lastDayAnswer = .lastDayOfMonth

        form.nextChargeDate = try day(2026, 11, 30)
        #expect(form.lastDayAnswer == nil)
        #expect(form.needsLastDayAnswer)

        form.lastDayAnswer = .lastDayOfMonth
        form.cyclePreset = .quarterly
        #expect(form.lastDayAnswer == nil)
    }

    @Test("an unambiguous mode B date is stored as the anchor unchanged")
    func modeBIdentity() throws {
        let form = try makeForm()
        form.entryMode = .nextCharge
        form.nextChargeDate = try day(2026, 8, 15)
        #expect(try #require(form.buildSubscription()).cycleStartDay == (try day(2026, 8, 15)))
    }

    // MARK: - Trial derivations

    @Test("trial conversion and cancel-by dates update live as the user types")
    func trialDerivations() throws {
        let form = try makeForm()
        form.isTrial = true
        form.trialStartDate = try day(2026, 8, 1)
        form.trialLengthDays = 14
        #expect(form.trialConversionDate == (try day(2026, 8, 15)))
        #expect(form.trialCancelByDate == (try day(2026, 8, 13)))

        form.trialLengthDays = 30
        #expect(form.trialConversionDate == (try day(2026, 8, 31)))
        #expect(form.trialCancelByDate == (try day(2026, 8, 29)))

        form.trialBufferDays = 5
        #expect(form.trialCancelByDate == (try day(2026, 8, 26)))
    }

    @Test("the trial toggle swaps the default lead days but never a chosen value")
    func trialLeadDefault() throws {
        let form = try makeForm()
        #expect(form.reminderLeadDays == 3)
        form.isTrial = true
        #expect(form.reminderLeadDays == 5)
        form.isTrial = false
        #expect(form.reminderLeadDays == 3)

        form.reminderLeadDays = 7
        form.isTrial = true
        #expect(form.reminderLeadDays == 7)
    }

    @Test("a trial form builds a trial-status subscription converting at the entered price")
    func trialBuild() throws {
        let form = try makeForm()
        form.isTrial = true
        form.trialStartDate = try day(2026, 8, 1)
        form.trialLengthDays = 14

        let subscription = try #require(form.buildSubscription())
        #expect(subscription.storedStatus == .trial)
        let trial = try #require(subscription.trial)
        #expect(trial.conversionDate == (try day(2026, 8, 15)))
        #expect(trial.convertsToAmountCents == 1099)
    }

    @Test("an impossible trial - zero length - blocks saving instead of storing garbage")
    func invalidTrialBlocksSave() throws {
        let form = try makeForm()
        form.isTrial = true
        form.trialLengthDays = 0
        #expect(!form.canSave)
    }

    // MARK: - Validation and building

    @Test("a blank name or missing amount blocks saving")
    func requiredFields() throws {
        let form = try makeForm()
        #expect(form.canSave)

        form.name = "   "
        #expect(!form.canSave)

        form.name = "Netflix"
        form.amount = nil
        #expect(!form.canSave)
    }

    @Test("the amount converts to integer cents exactly, rounded to the cent")
    func amountCents() throws {
        let form = try makeForm()
        form.amount = Decimal(string: "10.99")
        #expect(form.amountCents == 1099)
        form.amount = Decimal(string: "120")
        #expect(form.amountCents == 12000)
        form.amount = Decimal(string: "10.999")
        #expect(form.amountCents == 1100)
        form.amount = Decimal(string: "-1")
        #expect(form.amountCents == nil)
    }

    @Test("editing preserves identity, creation instant, and untouched fields")
    func editingPreserves() throws {
        let original = try makeSubscription(
            index: 1, name: "FoodApp", status: .active, cycleStartDay: try day(2026, 1, 15)
        )
        let form = SubscriptionFormModel(editing: original, dates: try fixedDates())
        form.name = "FoodApp+"

        let edited = try #require(form.buildSubscription())
        #expect(edited.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.updatedAt == Date(timeIntervalSince1970: 10_000))
        #expect(edited.cycleStartDay == original.cycleStartDay)
        #expect(edited.name == "FoodApp+")
    }

    @Test("editing a paused subscription keeps its status - the form is not a lifecycle flow")
    func editingKeepsLifecycleStatus() throws {
        let paused = try makeSubscription(
            index: 1, status: .paused, cycleStartDay: try day(2026, 1, 15),
            pauseEndsOn: try day(2026, 9, 1)
        )
        let form = SubscriptionFormModel(editing: paused, dates: try fixedDates())

        let edited = try #require(form.buildSubscription())
        #expect(edited.storedStatus == .paused)
        #expect(edited.pauseEndsOn == (try day(2026, 9, 1)))
    }

    @Test("editing a degraded .paused record - episode not yet arrived - still builds (spec §4a principle 2b)")
    func editingDegradedPausedBuilds() throws {
        // The parent synced in before its open episode (spec §4a): the read
        // holds it as an indefinite pause, and editing it must re-describe
        // that same shape through the describing constructor, not trap.
        let (degraded, repairs) = Subscription.readingRepaired(
            id: try fixtureUUID(1),
            name: "Gym",
            category: .other,
            status: .paused,
            amountCents: 4200,
            currencyCode: "CAD",
            cycle: .monthly,
            cycleStartDay: try day(2026, 1, 15),
            reminderLeadDays: 3,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        #expect(repairs == [.pausedWithoutOpenEpisode])
        let form = SubscriptionFormModel(editing: degraded, dates: try fixedDates())
        form.name = "Gym renamed"

        let edited = try #require(form.buildSubscription())
        #expect(edited.name == "Gym renamed")
        #expect(edited.storedStatus == .paused)
        #expect(edited.currentPauseEpisode == nil)
    }

    @Test("toggling the trial off builds an active subscription carrying the term's explicit tombstone")
    func trialToggleOff() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 1))
        let original = try makeSubscription(
            index: 1, status: .trial, cycleStartDay: try day(2026, 8, 1), trial: trial
        )
        let form = SubscriptionFormModel(editing: original, dates: try fixedDates())
        #expect(form.isTrial)

        form.isTrial = false
        let edited = try #require(form.buildSubscription())
        #expect(edited.storedStatus == .active)
        // The removal is an explicit deletion of the identified record - the
        // term rides along tombstoned, because a save infers nothing from
        // absence (spec §4a, Wave 6B-Prep).
        let dropped = try #require(edited.trial)
        #expect(dropped.id == trial.id)
        #expect(dropped.deletedAt == Date(timeIntervalSince1970: 10_000))
    }

    @Test("editing a confirmed-converted subscription preserves its trial term - history is not a toggle")
    func editingConvertedSubscriptionKeepsTrial() throws {
        // The state Wave 5's confirm flow produces: .active, anchored at the
        // conversion, trial term retained as the record of what happened.
        let trial = try makeTrialTerm(startDate: try day(2026, 7, 1))
        let converted = try makeSubscription(
            index: 1, status: .active, cycleStartDay: trial.conversionDate, trial: trial
        )
        let form = SubscriptionFormModel(editing: converted, dates: try fixedDates())
        #expect(!form.isTrial)

        // An unrelated edit - the price changed - must not delete the term.
        form.amount = 12.99
        let edited = try #require(form.buildSubscription())
        #expect(edited.trial == trial)
        #expect(edited.storedStatus == .active)
    }

    @Test("a lead of at least a whole cycle warns, and never blocks saving (spec §6.2, v1.4)")
    func leadCoveringCycleWarns() throws {
        let form = SubscriptionFormModel(dates: try fixedDates())
        form.name = "FoodApp"
        form.amount = 11
        form.cyclePreset = .weekly
        #expect(!form.leadCoversWholeCycle)

        form.reminderLeadDays = 7
        #expect(form.leadCoversWholeCycle)
        // Warn, don't block: the configuration is legal.
        #expect(form.canSave)

        form.cyclePreset = .monthly
        #expect(!form.leadCoversWholeCycle)
    }
}
