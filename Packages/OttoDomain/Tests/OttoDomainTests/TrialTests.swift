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
