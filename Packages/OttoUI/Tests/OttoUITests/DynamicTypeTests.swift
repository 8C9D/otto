// Renders the list row and the Today cards at the largest accessibility type size
// and asserts the layout grows to fit rather than clamping - the failure mode that
// produces truncation. UIKit-hosted, so this file runs on the simulator and
// compiles to nothing under `swift test` on a mac host.
#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
import OttoDomain
import OttoStores
@testable import OttoUI

@MainActor
@Suite("Dynamic Type at accessibility sizes")
struct DynamicTypeTests {

    /// iPhone SE width - the tightest layout Otto is likely to meet.
    private let narrowWidth: CGFloat = 320

    private func fittedHeight(of view: some View, at size: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(
            rootView: view.environment(\.dynamicTypeSize, size).frame(width: narrowWidth)
        )
        let fitted = host.sizeThatFits(
            in: CGSize(width: narrowWidth, height: UIView.layoutFittingCompressedSize.height)
        )
        return fitted.height
    }

    /// The layout must grow with the type size; a fixed-height row truncates
    /// instead, and that is exactly what this catches.
    private func assertGrows(
        _ view: some View,
        by factor: CGFloat = 1.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let regular = fittedHeight(of: view, at: .large)
        let accessibility = fittedHeight(of: view, at: .accessibility5)
        #expect(
            accessibility > regular * factor,
            "expected the AX5 layout (\(accessibility)pt) to grow well beyond the default (\(regular)pt)",
            sourceLocation: sourceLocation
        )
    }

    private var fixtures: PreviewFixtures {
        PreviewData.fixtures()
    }

    @Test("the subscription list row grows to the largest accessibility size")
    func listRow() throws {
        let subscriptions = fixtures.subscriptions
        let cancellations = Dictionary(
            uniqueKeysWithValues: fixtures.cancellations.map { ($0.subscriptionID, $0) }
        )
        let model = SubscriptionListModel()
        let rows = model.rows(
            subscriptions: subscriptions, cancellations: cancellations, today: PreviewData.today
        )
        try #require(!rows.isEmpty)
        for row in rows {
            assertGrows(SubscriptionRowView(row: row))
        }
    }

    @Test("every Today card grows to the largest accessibility size")
    func todayCards() throws {
        let cancellations = Dictionary(
            uniqueKeysWithValues: fixtures.cancellations.map { ($0.subscriptionID, $0) }
        )
        let overview = todayOverview(
            subscriptions: fixtures.subscriptions,
            cancellations: cancellations,
            from: PreviewData.today
        )
        let entries = overview.needsAction + overview.next30Days + overview.later
        try #require(!entries.isEmpty)
        for entry in entries {
            assertGrows(TodayEntryRow(entry: entry))
        }
    }

    @Test("the billing-event ledger row grows to the largest accessibility size")
    func ledgerRow() throws {
        let event = try #require(fixtures.events.first)
        assertGrows(BillingEventRow(event: event, currencyCode: "CAD"))
    }
}
#endif
