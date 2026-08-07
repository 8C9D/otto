import Foundation
import Testing
import OttoDomain

// The user enters the two things they actually know - start date and length - and the
// app derives the rest (spec §5.2). The user is never asked to do date arithmetic;
// that arithmetic failing is the reason this app exists.
@Suite("Trial calculations (spec §5.2)")
struct TrialTests {

    @Test("a 7-day trial from Aug 6 with a 2-day buffer converts Aug 13, cancel by Aug 11")
    func sevenDayTrial() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7)
        let aug13 = try day(2026, 8, 13)
        let aug11 = try day(2026, 8, 11)
        #expect(trial.conversionDate == aug13)
        #expect(trial.cancelByDate == aug11)
    }

    @Test("a buffer longer than the trial clamps cancel-by to the start date")
    func bufferLongerThanTrial() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7, bufferDays: 30)
        // Never a day before the trial existed, never negative arithmetic.
        #expect(trial.cancelByDate == trial.startDate)
    }

    @Test("trial dates cross month and year boundaries")
    func acrossYearBoundary() throws {
        let trial = try makeTrialTerm(startDate: try day(2026, 12, 28), lengthDays: 7, convertsToAmountCents: 999)
        let jan4 = try day(2027, 1, 4)
        let jan2 = try day(2027, 1, 2)
        #expect(trial.conversionDate == jan4)
        #expect(trial.cancelByDate == jan2)
    }

    @Test(
        "rejects a non-positive length, negative buffer, or negative converted price",
        arguments: [
            (lengthDays: 0, bufferDays: 2, convertsToAmountCents: 1100),
            (lengthDays: -7, bufferDays: 2, convertsToAmountCents: 1100),
            (lengthDays: 7, bufferDays: -1, convertsToAmountCents: 1100),
            (lengthDays: 7, bufferDays: 2, convertsToAmountCents: -1)
        ]
    )
    func rejectsInvalidTerms(lengthDays: Int, bufferDays: Int, convertsToAmountCents: Int) throws {
        let invalid = TrialTerm(
            id: try fixtureUUID(500),
            startDate: try day(2026, 8, 6),
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(invalid == nil)
    }
}

// Conversion is derived, never awaited (spec §5.2a): the founding failure is a user
// who is not paying attention, so no behaviour may depend on a tap or on a persisted
// status flip. These are the derivation's own tests; the planner, classifier, and
// materializer tests cover the consumers.
@Suite("Effective status (spec §5.2a)")
struct EffectiveStatusTests {

    // A 7-day trial from Aug 6: converts Aug 13 to $11.00/month.
    private func trialSubscription() throws -> Subscription {
        let start = try day(2026, 8, 6)
        let trial = try makeTrialTerm(startDate: start, lengthDays: 7, convertsToAmountCents: 1100)
        return try makeSubscription(status: .trial, cycle: .monthly, cycleStartDay: start, trial: trial)
    }

    @Test("before conversion a trial is a trial, billing at its stored anchor and amount")
    func beforeConversion() throws {
        let sub = try trialSubscription()
        let aug12 = try day(2026, 8, 12)
        #expect(sub.effectiveStatus(asOf: aug12) == .trial)
        #expect(sub.isConvertedTrial(asOf: aug12) == false)
        #expect(sub.billingAnchor(asOf: aug12) == sub.cycleStartDay)
        #expect(sub.billingAmountCents(asOf: aug12) == sub.amountCents)
    }

    @Test("on the conversion date a trial IS active, anchored at conversion, at the converted price")
    func onConversionDate() throws {
        let sub = try trialSubscription()
        let aug13 = try day(2026, 8, 13)
        #expect(sub.effectiveStatus(asOf: aug13) == .active)
        #expect(sub.isConvertedTrial(asOf: aug13))
        #expect(sub.billingAnchor(asOf: aug13) == (try day(2026, 8, 13)))
        #expect(sub.billingAmountCents(asOf: aug13) == 1100)
    }

    @Test("six weeks in a drawer changes nothing: the derivation needs no persisted flip")
    func longAfterConversion() throws {
        let sub = try trialSubscription()
        let sixWeeksOn = try day(2026, 9, 24)
        #expect(sub.effectiveStatus(asOf: sixWeeksOn) == .active)
        #expect(sub.billingAnchor(asOf: sixWeeksOn) == (try day(2026, 8, 13)))
    }

    @Test("non-trial statuses pass through untouched, even with a historical trial term attached")
    func nonTrialStatusesPassThrough() throws {
        // A persisted conversion: status already .active, the trial kept as history.
        let start = try day(2026, 8, 13)
        let trial = try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7)
        let sub = try makeSubscription(status: .active, cycle: .monthly, cycleStartDay: start, trial: trial)
        let later = try day(2026, 10, 1)
        #expect(sub.effectiveStatus(asOf: later) == .active)
        #expect(sub.isConvertedTrial(asOf: later) == false)
        // The stored anchor is already the rebased one; conversion must not re-derive.
        #expect(sub.billingAnchor(asOf: later) == start)
        #expect(sub.billingAmountCents(asOf: later) == sub.amountCents)
    }
}

// Spec §5.2b: a .trial subscription without a TrialTerm is unconstructible in process
// (precondition - not testable here) and undecodable from data (tested here). The
// mapping layer's refusal is tested in OttoPersistence.
@Suite("Model invariants (spec §5.2b)")
struct ModelInvariantTests {

    @Test("decoding a .trial subscription without a trial term fails loudly")
    func decodeRejectsTrialWithoutTerm() throws {
        let valid = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: try day(2026, 8, 6),
            trial: try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7)
        )
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
        )
        json.removeValue(forKey: "trial")
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Subscription.self, from: data)
        }
    }

    @Test("a valid trial subscription round-trips through Codable unchanged")
    func trialRoundTrips() throws {
        let valid = try makeSubscription(
            status: .trial, cycle: .monthly, cycleStartDay: try day(2026, 8, 6),
            trial: try makeTrialTerm(startDate: try day(2026, 8, 6), lengthDays: 7)
        )
        let decoded = try JSONDecoder().decode(Subscription.self, from: JSONEncoder().encode(valid))
        #expect(decoded == valid)
    }
}
