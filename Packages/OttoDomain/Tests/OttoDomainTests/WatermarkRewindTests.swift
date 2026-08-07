import Foundation
import Testing
@testable import OttoDomain

@Suite("Watermark rewind on edits (spec §5.3, v1.7)")
struct WatermarkRewindTests {

    private var today: CalendarDay { get throws { try day(2026, 8, 7) } }

    // MARK: - The founding case: a pause end pulled earlier

    @Test("pulling a pause's end date earlier rewinds to just before the newly expected charges")
    func pauseEndPulledEarlier() throws {
        let old = try makeSubscription(
            status: .paused,
            cycleStartDay: try day(2026, 1, 1),
            pauseEndsOn: try day(2026, 12, 1),
            lastMaterializedThrough: try day(2026, 12, 15)
        )
        var new = old
        new.pauseEndsOn = try day(2026, 9, 1)

        let rewound = watermarkAfterEdit(
            from: old, to: new, trackedSince: try day(2026, 1, 1), asOf: try today
        )

        // Sep 1 is the first charge the new sequence expects that the old one
        // never did; the watermark may vouch for nothing at or beyond it.
        #expect(rewound == (try day(2026, 8, 31)))
    }

    @Test("an edit that does not touch the sequence keeps the watermark")
    func unrelatedEdit() throws {
        let old = try makeSubscription(
            status: .active,
            cycleStartDay: try day(2026, 1, 1),
            lastMaterializedThrough: try day(2026, 9, 10)
        )
        var new = old
        new.notes = "renegotiated"
        new.amountCents = 1499

        let kept = watermarkAfterEdit(
            from: old, to: new, trackedSince: try day(2026, 1, 1), asOf: try today
        )

        #expect(kept == (try day(2026, 9, 10)))
    }

    @Test("moving the sequence later needs no rewind - invalidation owns the leftover rows")
    func pauseEndPushedLater() throws {
        let old = try makeSubscription(
            status: .paused,
            cycleStartDay: try day(2026, 1, 1),
            pauseEndsOn: try day(2026, 9, 1),
            lastMaterializedThrough: try day(2026, 12, 15)
        )
        var new = old
        new.pauseEndsOn = try day(2026, 12, 1)

        let kept = watermarkAfterEdit(
            from: old, to: new, trackedSince: try day(2026, 1, 1), asOf: try today
        )

        #expect(kept == (try day(2026, 12, 15)))
    }

    // MARK: - Transitions are not edits

    @Test("a status transition keeps the flows' watermark semantics instead of diffing sequences")
    func statusTransitionIsExcluded() throws {
        // An indefinite pause froze the watermark; the manual resume backfills
        // from that freeze (spec §5.3, v1.6). A naive sequence diff would read
        // the pause's deliberate silence as stranded charges and rewind to the
        // anchor - resurrecting the tombstoned in-pause rows.
        let old = try makeSubscription(
            status: .paused,
            cycleStartDay: try day(2026, 1, 1),
            lastMaterializedThrough: try day(2026, 8, 20)
        )
        var new = old
        new.storedStatus = .active

        let kept = watermarkAfterEdit(
            from: old, to: new, trackedSince: try day(2026, 1, 1), asOf: try today
        )

        #expect(kept == (try day(2026, 8, 20)))
    }

    // MARK: - The floor: no manufactured history

    @Test("an anchor corrected backwards rewinds only to the first tracked day")
    func anchorEditFlooredAtFirstRow() throws {
        let old = try makeSubscription(
            status: .active,
            cycleStartDay: try day(2026, 1, 25),
            lastMaterializedThrough: try day(2026, 9, 10)
        )
        let new = try makeSubscription(
            status: .active,
            cycleStartDay: try day(2026, 1, 5),
            lastMaterializedThrough: try day(2026, 9, 10)
        )

        let rewound = watermarkAfterEdit(
            from: old, to: new, trackedSince: try day(2026, 7, 25), asOf: try today
        )

        // Aug 5 is the first newly expected charge at or after the first row
        // ever created; Jan-Jul 5ths precede tracking and stay untracked.
        #expect(rewound == (try day(2026, 8, 4)))
    }

    @Test("with no ledger rows nothing before today was ever observed, so nothing rewinds behind it")
    func noRowsFloorsAtToday() throws {
        let old = try makeSubscription(
            status: .active,
            cycleStartDay: try day(2026, 1, 25),
            lastMaterializedThrough: try day(2026, 9, 10)
        )
        let new = try makeSubscription(
            status: .active,
            cycleStartDay: try day(2026, 1, 5),
            lastMaterializedThrough: try day(2026, 9, 10)
        )

        let rewound = watermarkAfterEdit(from: old, to: new, trackedSince: nil, asOf: try today)

        // The first newly expected charge on or after today is Sep 5; the
        // rewind stops just before it rather than inventing pre-entry history.
        #expect(rewound == (try day(2026, 9, 4)))
    }

    // MARK: - A save never advances the watermark

    @Test("the result never exceeds either record's watermark - only a ledger pass advances it")
    func neverAdvances() throws {
        let old = try makeSubscription(
            status: .active,
            cycleStartDay: try day(2026, 1, 1),
            lastMaterializedThrough: try day(2026, 9, 10)
        )
        var stale = old
        stale.lastMaterializedThrough = try day(2026, 9, 1)

        #expect(
            watermarkAfterEdit(from: old, to: stale, trackedSince: nil, asOf: try today)
                == (try day(2026, 9, 1))
        )
        #expect(
            watermarkAfterEdit(from: stale, to: old, trackedSince: nil, asOf: try today)
                == (try day(2026, 9, 1))
        )
    }

    @Test("records that never carried a watermark keep none")
    func nilStaysNil() throws {
        let old = try makeSubscription(status: .active, cycleStartDay: try day(2026, 1, 1))
        var new = old
        new.notes = "edited"

        #expect(watermarkAfterEdit(from: old, to: new, trackedSince: nil, asOf: try today) == nil)
    }
}
