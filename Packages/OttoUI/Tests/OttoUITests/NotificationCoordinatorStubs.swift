// The stubs `NotificationCoordinatorTests` needs to construct a coordinator at
// all, split out of that file when the F10 coalescing tests pushed it past
// SwiftLint's 400-line `file_length`. The seam is the one the file already
// named: nothing here is exercised by any assertion - the initializer requires
// these types, and stubbing is cheaper than reaching for the OttoServicesTests
// fakes, which that target cannot export.
//
// They lose `private`, which is file-scoped, and become internal to this test
// target. No rule was relaxed and no `excluded:` path was added.
#if os(iOS)
import Foundation
import OttoDomain
import OttoRepositories
import UserNotifications
@testable import OttoServices

// Nothing below is exercised by the assertions above; the coordinator's
// initializer requires them, and stubbing is cheaper than reaching for the
// OttoServicesTests fakes, which that target cannot export.

struct StubSubscriptionRepository: SubscriptionRepository {
    func save(_ subscription: Subscription) async throws {}
    func subscription(withID id: UUID) async throws -> Subscription? { nil }
    func subscriptions() async throws -> [Subscription] { [] }
    func subscriptionsIncludingDeleted() async throws -> [Subscription] { [] }
    func unreadableSubscriptionCount() async throws -> Int { 0 }
    func subscriptionReadRepairs() async throws -> [SubscriptionReadRepairReport] { [] }
    func deleteSubscription(withID id: UUID, at instant: Date) async throws {}
}

struct StubCancellationRepository: CancellationRepository {
    func save(_ episode: CancellationEpisode) async throws {}
    func openEpisode(forSubscription subscriptionID: UUID) async throws -> CancellationEpisode? { nil }
    func episodes(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] { [] }
    func episodesIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [CancellationEpisode] { [] }
}

struct StubBillingEventRepository: BillingEventRepository {
    func save(_ event: BillingEvent) async throws {}
    func events(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] { [] }
    func eventsIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [BillingEvent] { [] }
    func materializeEvents(
        for subscription: Subscription, from today: CalendarDay, horizonDays: Int,
        maxReminderLeadDays: Int, at instant: Date
    ) async throws -> [BillingEvent] { [] }
    func invalidateOutdatedUpcomingEvents(
        for subscription: Subscription, asOf today: CalendarDay, at instant: Date
    ) async throws -> [BillingEvent] { [] }
    func materializationWatermark(forSubscription subscriptionID: UUID) async throws -> CalendarDay? { nil }
    func initializeMaterializationWatermark(forSubscription subscriptionID: UUID, at day: CalendarDay) async throws {}
    func rewindMaterializationWatermark(forSubscription subscriptionID: UUID, to day: CalendarDay) async throws {}
}

struct StubPriceChangeRepository: PriceChangeRepository {
    func append(_ change: PriceChange) async throws {}
    func history(forSubscription subscriptionID: UUID) async throws -> [PriceChange] { [] }
    func historyIncludingDeleted(forSubscription subscriptionID: UUID) async throws -> [PriceChange] { [] }
}

struct StubNotificationClient: NotificationClient {
    func permission() async -> NotificationPermission { .authorized }
    func requestAuthorization() async -> NotificationPermission { .authorized }
    func pendingRequests() async -> [NotificationRequestSpec] { [] }
    func deliveredIdentifiers() async -> [String] { [] }
    func add(_ spec: NotificationRequestSpec) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) async {}
}

struct StubCenter: UserNotificationCentering {
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func installDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func deliveredNotificationIdentifiers() async -> [String] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}
#endif
