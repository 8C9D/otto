import Foundation
import Observation
import OttoDomain
import OttoRepositories

/// Everything the Insights screen shows, computed in one pass so the figures on
/// screen are mutually consistent - burn, categories, and the projection never
/// come from different snapshots of the data.
public struct InsightsData: Sendable {
    public var monthlyBurnCents: Int
    public var annualizedCents: Int
    public var categories: [CategoryBurn]
    public var next12Months: [MonthlyProjection]
    public var pausedLines: [PausedSpendLine]
    public var convertingSoon: [ConvertingTrial]
    public var zombies: [ZombieEntry]
    public var priceLog: [PriceChangeLogEntry]
    /// v1 is CAD-only (spec §2), but the code never assumes it: the currency
    /// shown is the one the subscriptions carry.
    public var currencyCode: String
    /// Whether any live subscription exists at all - the empty screen says
    /// something useful rather than a page of zeros (Wave 7 constraint 3).
    public var hasSubscriptions: Bool

    public init(
        monthlyBurnCents: Int,
        annualizedCents: Int,
        categories: [CategoryBurn],
        next12Months: [MonthlyProjection],
        pausedLines: [PausedSpendLine],
        convertingSoon: [ConvertingTrial],
        zombies: [ZombieEntry],
        priceLog: [PriceChangeLogEntry],
        currencyCode: String,
        hasSubscriptions: Bool
    ) {
        self.monthlyBurnCents = monthlyBurnCents
        self.annualizedCents = annualizedCents
        self.categories = categories
        self.next12Months = next12Months
        self.pausedLines = pausedLines
        self.convertingSoon = convertingSoon
        self.zombies = zombies
        self.priceLog = priceLog
        self.currencyCode = currencyCode
        self.hasSubscriptions = hasSubscriptions
    }
}

/// The observable state behind Insights (spec §7.2). Loads through the
/// repositories and calls the domain's pure functions; it computes nothing
/// itself, so every number on the screen has a tested derivation behind it.
@MainActor
@Observable
public final class InsightsStore {
    public private(set) var state: LoadState<InsightsData> = .loading

    private let subscriptionRepository: any SubscriptionRepository
    private let priceChangeRepository: any PriceChangeRepository
    private let dates: DateProvider

    public init(
        subscriptionRepository: any SubscriptionRepository,
        priceChangeRepository: any PriceChangeRepository,
        dates: DateProvider = .live
    ) {
        self.subscriptionRepository = subscriptionRepository
        self.priceChangeRepository = priceChangeRepository
        self.dates = dates
    }

    public func refresh() async {
        do {
            let subscriptions = try await subscriptionRepository.subscriptions()
            var priceChanges: [PriceChange] = []
            for subscription in subscriptions {
                priceChanges += try await priceChangeRepository.history(forSubscription: subscription.id)
            }
            let today = dates.today()
            state = .loaded(InsightsData(
                monthlyBurnCents: monthlyBurnCents(subscriptions: subscriptions, asOf: today),
                annualizedCents: annualizedTotalCents(subscriptions: subscriptions, asOf: today),
                categories: burnByCategory(subscriptions: subscriptions, asOf: today),
                next12Months: OttoDomain.next12Months(subscriptions: subscriptions, asOf: today),
                pausedLines: pausedSpendLines(
                    subscriptions: subscriptions, priceChanges: priceChanges, asOf: today
                ),
                convertingSoon: OttoDomain.convertingSoon(subscriptions: subscriptions, asOf: today),
                zombies: zombieReport(subscriptions: subscriptions, asOf: today),
                priceLog: priceChangeLog(subscriptions: subscriptions, priceChanges: priceChanges),
                currencyCode: subscriptions.first?.currencyCode ?? "CAD",
                hasSubscriptions: !subscriptions.isEmpty
            ))
        } catch {
            state = .failed(error)
        }
    }
}
