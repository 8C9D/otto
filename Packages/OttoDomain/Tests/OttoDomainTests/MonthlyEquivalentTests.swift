import Testing
import OttoDomain

// Normalisation rule (spec §7.2): monthly equivalent = amount x (30.4375 / cycle days),
// rounded only at this boundary, never stored.
@Suite("Monthly-equivalent normalisation")
struct MonthlyEquivalentTests {

    @Test("a monthly cycle is its own monthly equivalent")
    func monthly() {
        #expect(monthlyEquivalentCents(amountCents: 1099, cycle: .monthly) == 1099)
    }

    @Test("an annual cycle divides by exactly 12")
    func annual() {
        // 365.25 / 30.4375 == 12 exactly, so $120.00/yr is exactly $10.00/mo.
        #expect(monthlyEquivalentCents(amountCents: 12000, cycle: .annual) == 1000)
    }

    @Test("a quarterly cycle divides by exactly 3")
    func quarterly() {
        #expect(monthlyEquivalentCents(amountCents: 2997, cycle: .quarterly) == 999)
    }

    @Test("a weekly cycle multiplies by 30.4375 over 7")
    func weekly() {
        // 1000 x 30.4375 / 7 = 4348.214... rounds to 4348.
        #expect(monthlyEquivalentCents(amountCents: 1000, cycle: .weekly) == 4348)
    }

    @Test("a day cycle rounds half away from zero at the boundary")
    func fortyFiveDayCycle() throws {
        // 4500 x 30.4375 / 45 = 3043.75 - the half-cent case rounds up to 3044.
        let every45Days = try cycle(.day, 45)
        #expect(monthlyEquivalentCents(amountCents: 4500, cycle: every45Days) == 3044)
    }
}
