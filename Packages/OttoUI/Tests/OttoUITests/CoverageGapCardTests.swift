// The coverage-gap card's copy, split out of TodaySectionPlanTests.swift when
// item 9's copy matrix pushed that file past SwiftLint's 400-line file_length.
// Two suites: the deterministic wording rule (host, counted by verify.sh) and
// the rendered card (simulator only), `EmptyStateTests`' pattern.
import Foundation
import SwiftUI
import Testing
import OttoStores
@testable import OttoUI

/// R4-1's copy, and since round 5 item 9 (N3-5) the corrupt-date split.
/// Asserting the RENDERED string needs an accessibility tree this host does
/// not vend, but choosing between the wordings does not - and while that
/// choice was private the wordings could be swapped, so a whole failed pass
/// rendered "0 subscriptions couldn't be updated", with every test green.
@Suite("The coverage-gap card says the right one of its things")
struct CoverageGapCardTests {

    @Test("⛔ a whole failed pass never claims a count, least of all zero")
    func aWholePassFailureHasNoCount() {
        let card = CoverageGapCard(failureCount: 0)
        #expect(card.headline == "Reminders couldn't be updated")
        // The sentence this branch exists to prevent. `subscriptionCountText(0)`
        // rather than "0", so the assertion holds in a locale whose numbering
        // system does not use ASCII digits.
        #expect(!card.headline.contains(subscriptionCountText(0)))
        #expect(card.detail.contains("didn't finish"))
    }

    @Test("a partial failure names how many subscriptions, inflected, and no more than that")
    func aPartialFailureNamesTheCount() {
        // Compared against `subscriptionCountText`, not against a literal
        // "1 subscription": under a locale with its own numbering system that
        // phrase is "١ subscription", and pinning the ASCII form made this suite
        // fail on a host the run itself created as an evidence surface. The
        // branch is still pinned - swap the wordings and the count phrase is
        // absent from the headline entirely.
        // Exact equality, with the count phrase interpolated rather than
        // spelled out: that pins the WHOLE string and still holds in a locale
        // whose numbering system is not ASCII. `contains` alone would accept
        // "1 subscription subscriptions couldn't be updated".
        let one = CoverageGapCard(failureCount: 1)
        #expect(one.headline == "\(subscriptionCountText(1)) couldn't be updated")
        let three = CoverageGapCard(failureCount: 3)
        #expect(three.headline == "\(subscriptionCountText(3)) couldn't be updated")
        // The count is actually used, rather than a fixed phrase that happens
        // to contain one of them.
        #expect(one.headline != three.headline)
        // Wave 10 defect I: the inflection must be RESOLVED, not left as markup.
        #expect(!three.headline.contains("^["))
        #expect(three.detail.contains("their reminders"))
        // Round 5, item 9: transient failures NEVER borrow the corruption
        // copy - "unusable dates" and "on purpose" would tell a user with a
        // flaky pass to go fix dates that are fine.
        #expect(!three.headline.contains("unusable dates"))
        #expect(!three.detail.contains("on purpose"))
        #expect(three.detail.contains("it will try again"))
    }

    /// ⛔ Round 5, item 9 (N3-5). Reproduced at this stage's start by executing
    /// a real pass over one implausible-anchor subscription and rendering this
    /// card from its outcome: the copy read "1 subscription couldn't be
    /// updated" / "Otto couldn't refresh their reminders on its last check, so
    /// some may be missing. Nothing was deleted, and it will try again." -
    /// both sentences false for a subscription Otto silenced ON PURPOSE, which
    /// stays silent until the user repairs its dates. The wording below is the
    /// user's approved copy, verbatim.
    @Test("⛔ a corrupt-only pass says the dates are unusable, not that Otto will try again")
    func aCorruptOnlyPassGetsTheCorruptionCopy() {
        let one = CoverageGapCard(failureCount: 1, implausibleCount: 1)
        #expect(one.headline == "\(subscriptionCountText(1)) with unusable dates")
        let three = CoverageGapCard(failureCount: 3, implausibleCount: 3)
        #expect(three.headline == "\(subscriptionCountText(3)) with unusable dates")
        #expect(one.headline != three.headline)
        #expect(!three.headline.contains("^["))
        // The approved detail, whole: the deliberate stop, the reassurance,
        // and the repair with its resume promise.
        let expectedDetail = "Their stored dates aren't real calendar days, so Otto has stopped " +
            "their reminders on purpose. Nothing was deleted. Open each subscription and fix " +
            "its dates - reminders resume automatically once every date is fixed."
        #expect(one.detail == expectedDetail)
        #expect(three.detail == expectedDetail)
        // The false sentence this item removes must be GONE, not appended to.
        #expect(!one.detail.contains("try again"))
        #expect(!one.detail.contains("couldn't refresh"))
    }

    @Test("a mixed pass keeps the transient copy and appends the corruption sentences")
    func aMixedPassCarriesBothHalves() {
        let mixed = CoverageGapCard(failureCount: 3, implausibleCount: 1)
        // The headline stays the transient one, counting every failed
        // subscription - none of the three was updated.
        #expect(mixed.headline == "\(subscriptionCountText(3)) couldn't be updated")
        // Both halves, in order: the transient sentences for the genuine
        // failures, then the corruption sentences - the actionable half.
        #expect(mixed.detail.hasPrefix(
            "Otto couldn't refresh their reminders on its last check, so some may be missing. " +
            "Nothing was deleted, and it will try again."
        ))
        #expect(mixed.detail.contains(
            "Their stored dates aren't real calendar days, so Otto has stopped their reminders " +
            "on purpose. Open each subscription and fix its dates - reminders resume " +
            "automatically once every date is fixed."
        ))
        // "Nothing was deleted" once, not once per half.
        #expect(mixed.detail.components(separatedBy: "Nothing was deleted").count == 2)
    }

    @Test("the whole-pass failure wording is unchanged by the corruption split")
    func aWholePassFailureIsUntouched() {
        let card = CoverageGapCard(failureCount: 0, implausibleCount: 0)
        #expect(card.headline == "Reminders couldn't be updated")
        #expect(card.detail.contains("didn't finish"))
        #expect(!card.detail.contains("unusable"))
        #expect(!card.detail.contains("on purpose"))
    }
}

// MARK: - Rendering (simulator only)

#if canImport(UIKit)
import UIKit

/// The rendered half, `EmptyStateTests`' pattern via `UsageRepairRenderingTests`:
/// a pixel floor where no accessibility client exists, tree assertions where
/// one does. The card is new user-facing copy (round 5, item 9) and its own
/// doc comment says it has to be seen to be believed.
@MainActor
@Suite("The coverage-gap card renders its corrupt-date copy (N3-5)")
struct CoverageGapRenderingTests {

    private let screen = CGSize(width: 390, height: 844)

    private func host(_ card: CoverageGapCard) async -> UIWindow {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
            ?? UIWindow(frame: CGRect(origin: .zero, size: screen))
        window.frame = CGRect(origin: .zero, size: screen)
        window.rootViewController = UIHostingController(rootView: AnyView(List { card }))
        window.makeKeyAndVisible()
        for _ in 0 ..< 200 {
            window.rootViewController?.view.layoutIfNeeded()
            if !accessibilityLabels(in: window).isEmpty { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return window
    }

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

    /// `layer.render(in:)`, not `drawHierarchy` - the latter captures blank
    /// for a hosted window on this rig (`EmptyStateTests`' lesson).
    private func snapshot(_ window: UIWindow) -> Data? {
        window.rootViewController?.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        return image.pngData()
    }

    /// `EmptyStateTests`' floor: a capture with at most two distinct byte
    /// values drew nothing, and a difference between two blanks proves nothing.
    private func isVisuallyBlank(_ pixels: Data) -> Bool {
        let stride = max(1, pixels.count / 4096)
        var seen = Set<UInt8>()
        var index = 0
        while index < pixels.count {
            seen.insert(pixels[index])
            index += stride
        }
        return seen.count <= 2
    }

    @Test("⛔ the corrupt-date card draws, and differs from the transient card it replaced")
    func corruptCopyRenders() async throws {
        let corruptWindow = await host(CoverageGapCard(failureCount: 1, implausibleCount: 1))
        let transientWindow = await host(CoverageGapCard(failureCount: 1))

        // The pixel floor runs on every rig: the corrupt-only card either drew
        // different words than the transient card - the whole of item 9 - or
        // it did not. Byte-equal snapshots mean the branch never reached the
        // screen, and a blank capture means the comparison proved nothing.
        let corruptPixels = try #require(snapshot(corruptWindow))
        let transientPixels = try #require(snapshot(transientWindow))
        #expect(!isVisuallyBlank(corruptPixels), "the corrupt-copy card rendered blank")
        #expect(corruptPixels != transientPixels)

        // The string half needs an accessibility client, which this rig's
        // simulator does not attach; `EmptyStateTests` documents the pattern.
        let labels = accessibilityLabels(in: corruptWindow)
        if labels.isEmpty {
            withKnownIssue(
                "No accessibility client on this host, so UIKit vended no labels",
                isIntermittent: true
            ) {
                Issue.record("the rendered strings are reachable only through the accessibility tree")
            }
            return
        }
        #expect(labels.contains { $0.contains("with unusable dates") })
        #expect(labels.contains { $0.contains("stopped their reminders on purpose") })
        #expect(!labels.contains { $0.contains("it will try again") })
    }
}
#endif
