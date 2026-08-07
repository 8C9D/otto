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

    @Test("the dispute summary text grows to the largest accessibility size")
    func disputeSummaryText() throws {
        let summary = DisputeSummary(
            subscriptionName: "FoodApp",
            markedCancelledAt: PreviewData.now,
            evidenceNote: "Confirmation: 4821, spoke to Dana",
            chargeDate: try #require(CalendarDay(year: 2026, month: 8, day: 31)),
            chargeAmountCents: 1100,
            currencyCode: "CAD"
        )
        assertGrows(Text(summary.spokenText()).font(.callout))
    }

    @Test("the Insights zombie and converting-soon rows grow to the largest accessibility size")
    func insightsRows() throws {
        let subscription = try #require(fixtures.subscriptions.first)
        let zombie = ZombieEntry(
            subscription: subscription,
            lastUsedDate: CalendarDay(year: 2026, month: 5, day: 9),
            daysSinceUse: 90,
            costSinceCents: 5697,
            annualCostCents: 22788
        )
        assertGrows(ZombieRow(entry: zombie, currencyCode: "CAD"))

        let converting = ConvertingTrial(
            subscription: subscription,
            conversionDate: try #require(CalendarDay(year: 2026, month: 8, day: 13)),
            convertsToAmountCents: 950,
            monthlyEquivalent: 950,
            burnAfterCents: 2849
        )
        assertGrows(ConvertingTrialRow(entry: converting, currencyCode: "CAD"))
    }

    @Test("the payment-method row grows to the largest accessibility size")
    func paymentMethodRow() throws {
        let method = PaymentMethod(
            id: UUID(),
            label: "Bank Mastercard ••4821",
            last4: "4821",
            issuer: "Bank",
            expiryMonth: 9,
            expiryYear: 2026,
            isDefault: true,
            createdAt: PreviewData.now,
            updatedAt: PreviewData.now
        )
        assertGrows(PaymentMethodRow(
            method: method,
            load: PaymentMethodLoad(subscriptionCount: 3, monthlyCents: 4521),
            currencyCode: "CAD",
            today: PreviewData.today
        ))
    }

    @Test("the cancellation flow screen renders against the preview fixtures")
    func cancellationFlowRenders() throws {
        let subscription = try #require(fixtures.subscriptions.first)
        let host = UIHostingController(
            rootView: CancellationFlowView(subscription: subscription)
                .environment(PreviewData.model())
        )
        // A full screen, so it takes the proposed size rather than compressing;
        // rendering it at all is the assertion - a broken environment crashes.
        let screen = CGSize(width: 390, height: 844)
        host.view.frame = CGRect(origin: .zero, size: screen)
        host.view.layoutIfNeeded()
        #expect(host.sizeThatFits(in: screen).height > 0)
    }
}
#endif
