#if DEBUG
import Foundation
import OttoDomain
import OttoRepositories
import OttoStores

// In-memory repositories and fixture data for previews. Debug-only; the app's
// composition root injects the real persistence instead.

/// The preview data set, grouped so callers take what they need.
struct PreviewFixtures {
    var subscriptions: [Subscription] = []
    var cancellations: [CancellationEpisode] = []
    var events: [BillingEvent] = []
    var priceChanges: [PriceChange] = []
}

/// The fixed "today" every preview renders against: 2026-08-06.
enum PreviewData {
    static var today: CalendarDay {
        guard let day = CalendarDay(year: 2026, month: 8, day: 6) else {
            preconditionFailure("The preview date is invalid")
        }
        return day
    }

    static let now = Date(timeIntervalSince1970: 1_786_000_000)

    @MainActor
    static func model() -> AppModel {
        let repository = PreviewRepository()
        let model = AppModel(
            repositories: AppModel.Repositories(
                subscriptions: repository,
                billingEvents: repository,
                cancellations: repository,
                priceChanges: repository,
                paymentMethods: repository,
                transfer: repository
            ),
            // A throwaway suite: previews must not write the real defaults.
            settings: SettingsStore(
                userDefaults: UserDefaults(suiteName: "otto.previews") ?? .standard
            ),
            dates: .fixed(today: today, now: now)
        )
        return model
    }

    // MARK: - Fixtures, including the awkward cases

    static func fixtures() -> PreviewFixtures {
        var fixtures = PreviewFixtures()
        addNetflix(to: &fixtures)
        addFoodAppTrial(to: &fixtures)
        addPausedGym(to: &fixtures)
        addCancelledCrave(to: &fixtures)
        // An annual subscription beyond the 30-day horizon - the Later section.
        if let anchor = CalendarDay(year: 2025, month: 11, day: 12) {
            fixtures.subscriptions.append(subscription(
                index: 5, name: "iCloud+", category: .cloudAndStorage,
                amountCents: 12900, anchor: anchor, cycle: .annual
            ))
        }
        return fixtures
    }

    /// A 31-anchored monthly subscription - the clamping case - with a ledger
    /// and a price history.
    private static func addNetflix(to fixtures: inout PreviewFixtures) {
        guard let anchor = CalendarDay(year: 2026, month: 1, day: 31) else { return }
        let netflix = subscription(
            index: 1, name: "Netflix", category: .streamingAndVideo,
            amountCents: 2099, anchor: anchor
        )
        fixtures.subscriptions.append(netflix)
        if let expected = CalendarDay(year: 2026, month: 8, day: 31) {
            fixtures.events.append(BillingEvent(
                id: uuid(101), subscriptionID: netflix.id, expectedDate: expected,
                expectedAmountCents: 2099, state: .upcoming, createdAt: now, updatedAt: now
            ))
        }
        if let julyCharge = CalendarDay(year: 2026, month: 7, day: 31) {
            fixtures.events.append(BillingEvent(
                id: uuid(102), subscriptionID: netflix.id, expectedDate: julyCharge,
                expectedAmountCents: 2099, state: .confirmedCharged,
                userConfirmedAt: now, createdAt: now, updatedAt: now
            ))
        }
        if let effective = CalendarDay(year: 2026, month: 3, day: 31) {
            fixtures.priceChanges.append(PriceChange(
                id: uuid(201), subscriptionID: netflix.id, effectiveDate: effective,
                oldAmountCents: 1899, newAmountCents: 2099,
                source: .userEdit, note: "Standard plan price increase",
                createdAt: now, updatedAt: now
            ))
        }
    }

    /// A trial two days from conversion - inside its cancel-by window.
    private static func addFoodAppTrial(to fixtures: inout PreviewFixtures) {
        guard let trialStart = CalendarDay(year: 2026, month: 7, day: 25),
              let trial = TrialTerm(
                  id: uuid(501), startDate: trialStart, lengthDays: 14, bufferDays: 2,
                  convertsToAmountCents: 1099, createdAt: now, updatedAt: now
              ) else { return }
        fixtures.subscriptions.append(subscription(
            index: 2, name: "FoodApp", category: .foodAndDelivery,
            amountCents: 1099, anchor: trialStart, status: .trial, trial: trial
        ))
    }

    /// A paused subscription with a resume date.
    private static func addPausedGym(to fixtures: inout PreviewFixtures) {
        guard let anchor = CalendarDay(year: 2026, month: 2, day: 10),
              let resumes = CalendarDay(year: 2026, month: 9, day: 10) else { return }
        fixtures.subscriptions.append(subscription(
            index: 3, name: "GoodLife Fitness", category: .fitnessAndHealth,
            amountCents: 4200, anchor: anchor, status: .paused, pauseEndsOn: resumes
        ))
    }

    /// A cancelled subscription with a verification check due - and no payment
    /// method, like every fixture here (the awkward case is the default).
    private static func addCancelledCrave(to fixtures: inout PreviewFixtures) {
        guard let anchor = CalendarDay(year: 2026, month: 5, day: 20),
              let checkDate = CalendarDay(year: 2026, month: 8, day: 3) else { return }
        let cancelled = subscription(
            index: 4, name: "Crave", category: .streamingAndVideo,
            amountCents: 999, anchor: anchor, status: .cancelled
        )
        fixtures.subscriptions.append(cancelled)
        fixtures.cancellations.append(CancellationEpisode(
            id: uuid(601), subscriptionID: cancelled.id, markedCancelledAt: now,
            nextChargeDateIfNotCancelled: checkDate, verificationState: .pending,
            evidenceNotes: [EvidenceNote(
                id: uuid(611), text: "Confirmation #58291", createdAt: now, updatedAt: now
            )],
            createdAt: now, updatedAt: now
        ))
    }

    private static func subscription(
        index: Int,
        name: String,
        category: OttoDomain.Category,
        amountCents: Int,
        anchor: CalendarDay,
        cycle: BillingCycle = .monthly,
        status: SubscriptionStatus = .active,
        pauseEndsOn: CalendarDay? = nil,
        trial: TrialTerm? = nil
    ) -> Subscription {
        // A paused fixture needs its open episode (spec §5.3a) - the invariant
        // holds in previews too.
        let pauseEpisodes: [PauseEpisode] = status == .paused
            ? [PauseEpisode(
                id: uuid(index + 700),
                startedOn: anchor,
                scheduledResumeOn: pauseEndsOn,
                createdAt: now,
                updatedAt: now
            )]
            : []
        return Subscription(
            id: uuid(index),
            name: name,
            category: category,
            status: status,
            amountCents: amountCents,
            currencyCode: "CAD",
            cycle: cycle,
            cycleStartDay: anchor,
            reminderLeadDays: status == .trial ? 5 : 3,
            pauseEpisodes: pauseEpisodes,
            trial: trial,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))
            ?? UUID()
    }
}

#endif
