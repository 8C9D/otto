// Wave 10 defect J, put under test so it never needs a human again: the
// Subscriptions list rendered a completely BLANK screen when a status filter
// matched nothing, while the unfiltered empty list had its proper state -
// §7.1 requires saying so plainly, and the fix shipped with "verify by hand"
// because nothing in the suite could render the filtered-empty state. These
// tests render the real view against the preview fixtures and assert on what
// the screen actually vends: the accessibility tree (the rendered strings)
// and the clear-filter button's BEHAVIOR via accessibility activation.
// UIKit-hosted, so this file runs on the simulator and compiles to nothing
// under `swift test` on a mac host.
#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
import OttoDomain
import OttoStores
@testable import OttoUI

@MainActor
@Suite("Subscriptions list empty states (Wave 10, defect J)")
struct EmptyStateTests {

    private let screen = CGSize(width: 390, height: 844)

    /// A full screen must be hosted in a real window - a detached hosting
    /// controller vends an empty hierarchy (no accessibility elements, blank
    /// render), which is indistinguishable from defect J itself. The window is
    /// returned so callers keep it alive across assertions.
    ///
    /// `until` names the content the caller is about to assert on. Waiting for
    /// "any label at all" is not enough: a navigation bar vends labels before
    /// the list body exists, so the generic condition can return while the
    /// screen under test is still empty.
    private func host(
        _ view: some View,
        until isReady: ([String]) -> Bool = { !$0.isEmpty }
    ) async -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: screen))
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        await settle(window, until: isReady)
        return window
    }

    /// Lets SwiftUI build and lay out the hosted hierarchy: suspending on the
    /// main actor lets the main run loop turn, which is what the hosting view
    /// needs to materialize its subtree.
    ///
    /// Polls until the tree vends something rather than sleeping a fixed 300ms.
    /// The fixed wait was tuned on this project's Mac and failed every test in
    /// this suite on a GitHub `macos-26` runner, which took roughly 3x as long
    /// to render - a fixed budget encodes the speed of one machine.
    ///
    /// ⚠ This lowers the probability of a spurious failure; it does NOT resolve
    /// the ambiguity recorded in DECISIONS.md. A hierarchy that never
    /// materializes still vends no accessibility elements, which is
    /// indistinguishable from defect J having returned. On timeout the suite
    /// reports a failure it cannot attribute - that limit is structural, and
    /// the timeout only decides how long it waits before hitting it.
    private func settle(
        _ window: UIWindow,
        until isReady: ([String]) -> Bool = { !$0.isEmpty }
    ) async {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            window.rootViewController?.view.layoutIfNeeded()
            for _ in 0..<8 { await Task.yield() }
            if isReady(accessibilityLabels(in: window)) { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        window.rootViewController?.view.layoutIfNeeded()
    }

    /// Every accessibility label the hosted hierarchy vends - the rendered
    /// strings a VoiceOver user hears, which is as close to "what is on
    /// screen" as a hosted test can honestly read.
    private func accessibilityLabels(in root: UIView) -> [String] {
        elements(in: root).compactMap(\.accessibilityLabel)
    }

    private func elements(in root: NSObject) -> [NSObject] {
        var found: [NSObject] = []
        var queue: [NSObject] = [root]
        while let next = queue.popLast() {
            found.append(next)
            if let elements = next.accessibilityElements as? [NSObject] {
                queue.append(contentsOf: elements)
            }
            let count = next.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let element = next.accessibilityElement(at: index) as? NSObject {
                        queue.append(element)
                    }
                }
            }
            if let view = next as? UIView {
                queue.append(contentsOf: view.subviews)
            }
        }
        return found
    }

    /// A non-blank render has pixels that differ; defect J's failure mode was
    /// a screen with nothing on it at all.
    private func isVisuallyBlank(_ view: UIView) -> Bool {
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data as Data? else { return true }
        let stride = max(1, data.count / 4096)
        var seen = Set<UInt8>()
        var index = 0
        while index < data.count {
            seen.insert(data[index])
            index += stride
        }
        return seen.count <= 2
    }

    /// A loaded model over the preview fixtures: five subscriptions, none of
    /// them archived - so the Archived filter is the filtered-empty case over
    /// a NON-empty list, which is exactly the shape that shipped blank.
    private func loadedModel() async -> AppModel {
        let model = PreviewData.model()
        await model.subscriptionsStore.refresh()
        return model
    }

    @Test("⛔ a filter that matches nothing renders the named empty state, not a blank screen")
    func filteredEmptyStateRenders() async throws {
        let model = await loadedModel()
        if case .loaded(let subscriptions) = model.subscriptionsStore.subscriptions {
            try #require(!subscriptions.isEmpty)
        }
        let listModel = SubscriptionListModel()
        listModel.statusFilter = .archived

        let window = await host(SubscriptionsView(listModel: listModel).environment(model)) { labels in
            labels.contains { $0.contains("No Archived subscriptions") }
        }
        let labels = accessibilityLabels(in: window)

        #expect(labels.contains { $0.contains("No Archived subscriptions") })
        #expect(labels.contains { $0.contains("Nothing matches this status filter") })
        #expect(labels.contains { $0.contains("Show All Statuses") })
        #expect(!isVisuallyBlank(window))
    }

    @Test("the unfiltered empty list still says 'No subscriptions yet' with its Add action")
    func unfilteredEmptyStateRenders() async throws {
        // Two empty cases exist and the whole defect was implementing one of
        // them; this pins the other. Empty the store through its own API.
        let model = await loadedModel()
        guard case .loaded(let subscriptions) = model.subscriptionsStore.subscriptions else {
            Issue.record("fixtures failed to load")
            return
        }
        for subscription in subscriptions {
            try await model.subscriptionsStore.delete(subscriptionID: subscription.id)
        }
        await model.subscriptionsStore.refresh()

        let window = await host(SubscriptionsView().environment(model)) { labels in
            labels.contains { $0.contains("No subscriptions yet") }
        }
        let labels = accessibilityLabels(in: window)

        #expect(labels.contains { $0.contains("No subscriptions yet") })
        #expect(labels.contains { $0.contains("Add Subscription") })
    }

    @Test("⛔ the clear-filter action WORKS: activating it clears the filter and the rows come back")
    func clearFilterActionRestoresList() async throws {
        let model = await loadedModel()
        let listModel = SubscriptionListModel()
        listModel.statusFilter = .archived

        let window = await host(SubscriptionsView(listModel: listModel).environment(model)) { labels in
            labels.contains { $0.contains("Show All Statuses") }
        }
        let button = try #require(elements(in: window).first {
            ($0.accessibilityLabel?.contains("Show All Statuses") ?? false)
                && $0.accessibilityTraits.contains(.button)
        })

        #expect(button.accessibilityActivate())
        #expect(listModel.statusFilter == nil)

        // Re-render with the cleared filter: the rows are back. The default
        // "any label at all" condition would return instantly here - the
        // filtered-empty labels are still on screen - so this waits for the
        // specific change the assertion is about.
        await settle(window) { labels in
            labels.contains { $0.contains("Claude") || $0.contains("Netflix") }
        }
        let relabelled = accessibilityLabels(in: window)
        #expect(relabelled.contains { $0.contains("Claude") || $0.contains("Netflix") })
        #expect(!relabelled.contains { $0.contains("No Archived subscriptions") })
    }

    @Test("the payment-method row's RENDERED copy is inflected - no morphology residue (defect I, view level)")
    func paymentMethodRowRendersInflectedCopy() async throws {
        // Wave 10's defect-I test asserted on the helper only; this covers the
        // composed sentence as the row actually renders it.
        let method = PaymentMethod(
            id: UUID(), label: "Credit card", last4: "4821", issuer: "Bank",
            expiryMonth: 2, expiryYear: 2028, isDefault: true,
            createdAt: PreviewData.now, updatedAt: PreviewData.now
        )
        let window = await host(PaymentMethodRow(
            method: method,
            load: PaymentMethodLoad(subscriptionCount: 3, monthlyCents: 29866),
            currencyCode: "CAD",
            today: PreviewData.today
        )) { labels in
            labels.contains { $0.contains("billed to this card") }
        }
        let labels = accessibilityLabels(in: window)

        #expect(labels.contains { $0.contains("3 subscriptions billed to this card") })
        #expect(!labels.contains { $0.contains("^[") || $0.contains("inflect") })
    }
}
#endif
