// N4-16 (round 5, item 4): `lastUsedDate` has exactly one writer in the app -
// the Usage section's "I used this today" button - and the section was gated
// on the ACTIVE effective status, so a corrupt `lastUsedDate` on a paused,
// trial or cancelled subscription had no in-app repair at all: the user's
// only path was a status change they did not want (`docs/next-wave.md` said
// so in as many words).
//
// The guard is layered the way this rig can actually falsify it:
// `VisibilityRuleTests` pins the whole status-by-plausibility matrix on the
// extracted predicate and runs deterministically on every host, and the
// rendering suite below proves the real section draws and (where an
// accessibility client exists) that its activation writes the repair.
import Foundation
import SwiftUI
import Testing
import OttoDomain
import OttoStores
@testable import OttoUI

/// Shared fixtures for both suites.
enum UsageRepairFixtures {
    static let today = CalendarDay(year: 2026, month: 8, day: 12)
    /// What a pre-F1 build stored on a Buddhist device - the corrupt day the
    /// repair exists for.
    static let corruptDay = CalendarDay(year: 2569, month: 8, day: 6)
    static let healthyDay = CalendarDay(year: 2026, month: 8, day: 1)

    static func subscription(
        status: SubscriptionStatus,
        lastUsedDate: CalendarDay?
    ) throws -> Subscription {
        guard let anchor = CalendarDay(year: 2026, month: 8, day: 6) else {
            throw FixtureFailure.badLiteral
        }
        let pauses: [PauseEpisode] = status == .paused
            ? [PauseEpisode(
                id: UUID(), startedOn: CalendarDay(year: 2026, month: 8, day: 1),
                scheduledResumeOn: nil,
                createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0)
            )]
            : []
        let trial: TrialTerm? = status == .trial
            ? TrialTerm(
                id: UUID(), startDate: anchor.adding(days: 4),
                lengthDays: 30, bufferDays: 2, convertsToAmountCents: 1099,
                createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0)
            )
            : nil
        if status == .trial && trial == nil { throw FixtureFailure.badLiteral }
        return Subscription(
            id: UUID(), name: "Fixture", category: .other, status: status,
            amountCents: 1099, currencyCode: "CAD", cycle: .monthly,
            cycleStartDay: anchor, reminderLeadDays: 3,
            pauseEpisodes: pauses, trial: trial, lastUsedDate: lastUsedDate,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    enum FixtureFailure: Error { case badLiteral }
}

/// The deterministic half: every status against every `lastUsedDate` state,
/// on the predicate the view renders from. Runs under `swift test` on the
/// host, so `verify.sh` counts it on every rig.
@Suite("The usage section's visibility rule (N4-16)")
struct VisibilityRuleTests {

    private static let nonActive: [SubscriptionStatus] = [.paused, .trial, .cancelled]

    @Test("⛔ a corrupt lastUsedDate shows the section on every non-active status", arguments: [
        SubscriptionStatus.paused, .trial, .cancelled
    ])
    func corruptShowsRepair(status: SubscriptionStatus) throws {
        let today = try #require(UsageRepairFixtures.today)
        let corrupt = try UsageRepairFixtures.subscription(
            status: status, lastUsedDate: try #require(UsageRepairFixtures.corruptDay)
        )
        #expect(UsageSectionView.isShown(for: corrupt, asOf: today))
        #expect(UsageSectionView.needsLastUsedDateRepair(corrupt, asOf: today))
    }

    @Test("a healthy lastUsedDate keeps the section active-only", arguments: [
        SubscriptionStatus.paused, .trial, .cancelled
    ])
    func healthyStaysHidden(status: SubscriptionStatus) throws {
        let today = try #require(UsageRepairFixtures.today)
        let healthy = try UsageRepairFixtures.subscription(
            status: status, lastUsedDate: UsageRepairFixtures.healthyDay
        )
        #expect(!UsageSectionView.isShown(for: healthy, asOf: today))
    }

    @Test("a never-recorded lastUsedDate offers no repair off the active state", arguments: [
        SubscriptionStatus.paused, .trial, .cancelled
    ])
    func nilOffersNoRepair(status: SubscriptionStatus) throws {
        // nil is not corruption: the check-in counts from the anchor instead.
        let today = try #require(UsageRepairFixtures.today)
        let never = try UsageRepairFixtures.subscription(status: status, lastUsedDate: nil)
        #expect(!UsageSectionView.isShown(for: never, asOf: today))
        #expect(!UsageSectionView.needsLastUsedDateRepair(never, asOf: today))
    }

    @Test("an active subscription shows the section whatever lastUsedDate holds")
    func activeUnchanged() throws {
        let today = try #require(UsageRepairFixtures.today)
        for lastUsed in [UsageRepairFixtures.healthyDay, UsageRepairFixtures.corruptDay, nil] {
            let active = try UsageRepairFixtures.subscription(status: .active, lastUsedDate: lastUsed)
            #expect(UsageSectionView.isShown(for: active, asOf: today))
        }
    }

    @Test("the repair rule applies the plausibility rule, not a private threshold")
    func ruleMatchesPlausibility() throws {
        // The boundary day (70 years behind) is plausible, so no repair is
        // offered for it - the predicate must not reach past the rule it
        // applies, or a real 1956 date would grow a spurious repair button.
        let today = try #require(UsageRepairFixtures.today)
        let boundary = try #require(CalendarDay(year: 1956, month: 8, day: 12))
        let atBoundary = try UsageRepairFixtures.subscription(status: .paused, lastUsedDate: boundary)
        #expect(!UsageSectionView.needsLastUsedDateRepair(atBoundary, asOf: today))
    }
}

// MARK: - Rendering (simulator only)

#if canImport(UIKit)
import UIKit

/// The rendered half, `EmptyStateTests`' pattern: accessibility-tree
/// assertions where a client exists, a pixel floor where none does - on this
/// project's usual rig the tree is empty, so the floor is what actually runs,
/// and the label/activation halves are recorded as known issues rather than
/// silently skipped.
@MainActor
@Suite("The usage repair renders (N4-16)")
struct UsageRepairRenderingTests {

    private let screen = CGSize(width: 390, height: 844)

    private func makeModel(
        seeded subscription: Subscription, suite: String
    ) async throws -> (AppModel, PreviewRepository) {
        let repository = PreviewRepository()
        try await repository.save(subscription)
        let today = try #require(UsageRepairFixtures.today)
        let model = AppModel(
            repositories: AppModel.Repositories(
                subscriptions: repository, billingEvents: repository,
                cancellations: repository, priceChanges: repository,
                paymentMethods: repository, transfer: repository
            ),
            notifications: nil,
            settings: SettingsStore(
                userDefaults: UserDefaults(suiteName: suite) ?? .standard
            ),
            dates: .fixed(today: today)
        )
        return (model, repository)
    }

    private func hostSection(
        for subscription: Subscription, model: AppModel,
        until isReady: @escaping ([String]) -> Bool
    ) async -> UIWindow {
        // The same shape as `SubscriptionDetailView.perform`, minus the
        // refresh: run the action, and surface a failure as a test issue
        // rather than swallowing it.
        let perform: (@escaping () async throws -> Void) -> Void = { work in
            Task { @MainActor in
                do { try await work() } catch { Issue.record("perform failed: \(error)") }
            }
        }
        let detail = SubscriptionDetail(
            subscription: subscription, events: [], priceHistory: [],
            cancellation: nil, paymentMethod: nil
        )
        let view = Form { UsageSectionView(detail: detail, perform: perform) }
            .environment(model)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:))
            ?? UIWindow(frame: CGRect(origin: .zero, size: screen))
        window.frame = CGRect(origin: .zero, size: screen)
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        await settle(window, until: isReady)
        return window
    }

    private func settle(
        _ window: UIWindow, upTo attempts: Int = 200,
        until isReady: ([String]) -> Bool
    ) async {
        for _ in 0 ..< attempts {
            window.rootViewController?.view.layoutIfNeeded()
            if isReady(accessibilityLabels(in: window)) { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
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
    /// for a hosted window on this rig, which `EmptyStateTests` learned first.
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

    @Test("⛔ the repair section draws for a corrupt paused subscription where none drew before")
    func corruptPausedRenders() async throws {
        let corrupt = try UsageRepairFixtures.subscription(
            status: .paused, lastUsedDate: try #require(UsageRepairFixtures.corruptDay)
        )
        let healthy = try UsageRepairFixtures.subscription(
            status: .paused, lastUsedDate: UsageRepairFixtures.healthyDay
        )
        let (corruptModel, _) = try await makeModel(seeded: corrupt, suite: "usage-render-corrupt")
        let (healthyModel, _) = try await makeModel(seeded: healthy, suite: "usage-render-healthy")

        let corruptWindow = await hostSection(for: corrupt, model: corruptModel) { labels in
            labels.contains { $0.contains("I used this today") }
        }
        let healthyWindow = await hostSection(for: healthy, model: healthyModel) { _ in false }

        // The pixel floor runs on every rig: the section either drew rows into
        // the corrupt window or it did not, and the healthy window - same
        // status, plausible day - is the empty-form control it must differ
        // from. Byte-equal snapshots mean the fix did not render, and a blank
        // corrupt capture means the comparison proved nothing.
        let corruptPixels = try #require(snapshot(corruptWindow))
        let healthyPixels = try #require(snapshot(healthyWindow))
        #expect(!isVisuallyBlank(corruptPixels), "the corrupt window rendered blank")
        #expect(corruptPixels != healthyPixels)

        // The label half needs an accessibility client, which this rig's
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
        #expect(labels.contains { $0.contains("I used this today") })
        // The corrupt value is on screen beside the repair, so the user can
        // see what they are fixing: the era-numbered year renders as-is.
        #expect(labels.contains { $0.contains("2569") })
    }

    @Test("⛔ activating the repair on a paused subscription writes today into lastUsedDate")
    func repairWrites() async throws {
        let corrupt = try UsageRepairFixtures.subscription(
            status: .paused, lastUsedDate: try #require(UsageRepairFixtures.corruptDay)
        )
        let (model, repository) = try await makeModel(seeded: corrupt, suite: "usage-repair-writes")
        let window = await hostSection(for: corrupt, model: model) { labels in
            labels.contains { $0.contains("I used this today") }
        }

        // Reachable only through the accessibility tree - reported rather
        // than silently skipped where no client exists, like the clear-filter
        // activation in `EmptyStateTests`. The model-level write path itself
        // is guarded host-side by `RecordUsageTests` in OttoServicesTests.
        guard let button = elements(in: window).first(where: {
            ($0.accessibilityLabel?.contains("I used this today") ?? false)
                && $0.accessibilityTraits.contains(.button)
        }) else {
            withKnownIssue(
                "No accessibility client on this host, so UIKit vended no labels",
                isIntermittent: true
            ) {
                Issue.record("activation is reachable only through the accessibility tree")
            }
            return
        }
        #expect(button.accessibilityActivate())

        let today = try #require(UsageRepairFixtures.today)
        var repaired: CalendarDay?
        for _ in 0 ..< 200 {
            repaired = try await repository.subscription(withID: corrupt.id)?.lastUsedDate
            if repaired == today { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(repaired == today)
    }
}
#endif
