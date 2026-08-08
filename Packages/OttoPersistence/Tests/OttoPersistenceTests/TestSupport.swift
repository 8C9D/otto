import Foundation
import OttoDomain
import OttoRepositories
import SwiftData
import Testing
@testable import OttoPersistence

/// Unwraps a validated `CalendarDay`, failing the calling test at its own line.
func day(
    _ year: Int,
    _ month: Int,
    _ dayOfMonth: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> CalendarDay {
    try #require(CalendarDay(year: year, month: month, day: dayOfMonth), sourceLocation: sourceLocation)
}

/// A deterministic UUID so fixture failures reproduce identically run to run.
func fixtureUUID(
    _ index: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> UUID {
    let uuidString = String(format: "00000000-0000-0000-0000-%012d", index)
    return try #require(UUID(uuidString: uuidString), sourceLocation: sourceLocation)
}

/// The serialized root every suite in this target nests under.
///
/// SwiftData keeps a process-global, name-keyed model registry, and this
/// package deliberately declares TWO schema versions whose classes share
/// entity names - V1 is the migration source and must match shipped stores
/// byte for byte. Concurrent activity across the two versions (the migration
/// test's V1 phase against any other test's V2 objects) races that registry
/// and dies in SwiftData's ModelCoders. The app never does this - it builds
/// exactly one container - so this is a test-environment hazard only, closed
/// by running the whole target serially. The suites are sub-second; the
/// parallelism given up is noise.
@Suite(.serialized)
struct SerializedPersistenceTests {}

/// Serializes every `ModelContainer` creation in this test target. SwiftData
/// keeps a process-global, name-keyed model registry, and this package
/// deliberately declares two schema versions whose classes SHARE entity names
/// (V1 is the migration source and must match the shipped store byte for
/// byte). Building a V1 and a V2 schema concurrently races that registry and
/// dies in ModelCoders - a test-environment hazard only, since the app builds
/// exactly one container. Creation is the registration point, so excluding
/// concurrent creation is sufficient; concurrent USE of already-built
/// containers is safe.
let containerCreationLock = NSLock()

/// A fresh isolated in-memory store per test. The tuple's second element is
/// the container PAIR (main + device state) so a test can open its own context
/// on the main store or build a second `OttoStore` over the same data.
/// `syncState` is pinned (default: sync off) rather than read from the
/// process's real `UserDefaults`, so tests are deterministic; pass an engaged
/// or enabled state to exercise the §8 restore guard.
func makeStore(syncState: SyncState = SyncState()) throws -> (store: OttoStore, containers: OttoContainers) {
    containerCreationLock.lock()
    defer { containerCreationLock.unlock() }
    let containers = try OttoContainerFactory.inMemoryContainers()
    return (OttoStore(containers: containers, syncState: { syncState }), containers)
}

/// A fully populated subscription so round-trips exercise every field.
///
/// `pauseEndsOn` is double-optional so tests can say three things: omit it for
/// the automatic anchor+60 date a `.paused` fixture gets (full-field round-trip
/// coverage), pass a day to pin the resume, or pass `.some(nil)` for an
/// indefinite pause - which since spec v1.6 behaves differently from a dated one.
func makeSubscription(
    index: Int = 0,
    status: SubscriptionStatus = .active,
    amountCents: Int = 1099,
    cycle: BillingCycle = .monthly,
    cycleStartDay: CalendarDay,
    pauseEndsOn: CalendarDay?? = nil,
    pauseEpisodes: [PauseEpisode]? = nil,
    trial: TrialTerm? = nil,
    deletedAt: Date? = nil
) throws -> Subscription {
    // A `.paused` fixture carries its open episode (spec §5.3a), with the same
    // automatic dates the old field pair got so full-field round-trips still
    // exercise every column.
    let episodes: [PauseEpisode]
    if let pauseEpisodes {
        episodes = pauseEpisodes
    } else if status == .paused {
        episodes = [PauseEpisode(
            id: try fixtureUUID(index + 700),
            startedOn: cycleStartDay.adding(days: 30),
            scheduledResumeOn: pauseEndsOn ?? cycleStartDay.adding(days: 60),
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )]
    } else {
        episodes = []
    }
    return Subscription(
        id: try fixtureUUID(index),
        name: "Fixture \(index)",
        vendorURL: URL(string: "https://example.com/account"),
        category: .foodAndDelivery,
        status: status,
        amountCents: amountCents,
        currencyCode: "CAD",
        cycle: cycle,
        cycleStartDay: cycleStartDay,
        reminderLeadDays: 3,
        sameDayReminder: true,
        pauseEpisodes: episodes,
        trial: trial,
        paymentMethodID: try fixtureUUID(900),
        cancellationURL: URL(string: "https://example.com/cancel"),
        cancellationNotes: "phone only, mention retention offer",
        lastUsedDate: cycleStartDay.adding(days: 10),
        notes: "a note",
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000),
        deletedAt: deletedAt
    )
}

func makeBillingEvent(index: Int = 100, subscriptionID: UUID, expectedDate: CalendarDay) throws -> BillingEvent {
    BillingEvent(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        expectedDate: expectedDate,
        expectedAmountCents: 1099,
        state: .confirmedCharged,
        userConfirmedAt: Date(timeIntervalSince1970: 3_000),
        acknowledgedAt: Date(timeIntervalSince1970: 3_500),
        actualAmountCents: 1299,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

/// A validated, fully populated trial term.
func makeTrialTerm(
    index: Int = 500,
    startDate: CalendarDay,
    lengthDays: Int = 14,
    bufferDays: Int = 2,
    convertsToAmountCents: Int = 1599,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> TrialTerm {
    try #require(
        TrialTerm(
            id: try fixtureUUID(index),
            startDate: startDate,
            lengthDays: lengthDays,
            bufferDays: bufferDays,
            convertsToAmountCents: convertsToAmountCents,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ),
        sourceLocation: sourceLocation
    )
}

func makeCancellationEpisode(
    index: Int = 600,
    subscriptionID: UUID,
    nextChargeDateIfNotCancelled: CalendarDay,
    expectedChargeAmountCents: Int? = 1099,
    verificationState: CancellationEpisode.VerificationState = .pending,
    unansweredCheckCount: Int = 0,
    evidenceNote: String? = nil
) throws -> CancellationEpisode {
    CancellationEpisode(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        markedCancelledAt: Date(timeIntervalSince1970: 4_000),
        nextChargeDateIfNotCancelled: nextChargeDateIfNotCancelled,
        expectedChargeAmountCents: expectedChargeAmountCents,
        verificationState: verificationState,
        unansweredCheckCount: unansweredCheckCount,
        evidenceNotes: try evidenceNote.map { text in
            [EvidenceNote(
                id: try fixtureUUID(index + 50),
                text: text,
                createdAt: Date(timeIntervalSince1970: 1_500),
                updatedAt: Date(timeIntervalSince1970: 1_500)
            )]
        } ?? [],
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func makePriceChange(
    index: Int = 200,
    subscriptionID: UUID,
    effectiveDate: CalendarDay,
    source: PriceChange.Source = .userEdit,
    note: String? = nil
) throws -> PriceChange {
    PriceChange(
        id: try fixtureUUID(index),
        subscriptionID: subscriptionID,
        effectiveDate: effectiveDate,
        oldAmountCents: 1099,
        newAmountCents: 1299,
        source: source,
        note: note,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

func makePaymentMethod(index: Int = 300, label: String = "Bank Mastercard ..4821", isDefault: Bool = true) throws -> PaymentMethod {
    PaymentMethod(
        id: try fixtureUUID(index),
        label: label,
        last4: "4821",
        issuer: "Bank",
        expiryMonth: 11,
        expiryYear: 2027,
        isDefault: isDefault,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 2_000)
    )
}

// MARK: - The §5.0a store-wide id invariant

/// Every id that more than one LIVE record carries - across the WHOLE main
/// store, not per table, because CloudKit record names are unique per zone
/// regardless of record type (spec §5.0a): two live records sharing an id is
/// a name collision in exactly the subsystem 6B enables. Tombstones are
/// excluded - they are communicable history, not addressable live records.
func duplicateLiveIDs(in containers: OttoContainers) throws -> [UUID] {
    let context = ModelContext(containers.main)
    var counts: [UUID: Int] = [:]
    func count<Record: PersistentModel>(
        _ type: Record.Type, id: (Record) -> UUID?, deletedAt: (Record) -> Date?
    ) throws {
        for record in try context.fetch(FetchDescriptor<Record>()) where deletedAt(record) == nil {
            if let id = id(record) { counts[id, default: 0] += 1 }
        }
    }
    try count(StoredSubscription.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredTrialTerm.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredBillingEvent.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredCancellationEpisode.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredEvidenceNote.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredPauseEpisode.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredPriceChange.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    try count(StoredPaymentMethod.self, id: { $0.id }, deletedAt: { $0.deletedAt })
    return counts.filter { $0.value > 1 }.map(\.key).sorted { $0.uuidString < $1.uuidString }
}

// MARK: - On-disk migration helpers (shared by the migration suites)

/// The whole legacy-touching phase holds the shared creation lock (see
/// TestSupport): building the V1/V2 schemas while another test builds V3
/// races SwiftData's name-keyed registry. Synchronous so the lock is legal.
func migratedStore(
    at url: URL, deviceStateURL: URL, seed: (URL) throws -> Void
) throws -> (store: OttoStore, containers: OttoContainers) {
    containerCreationLock.lock()
    defer { containerCreationLock.unlock() }
    try seed(url)
    // Reopen through the factory - what the app does on first launch
    // after the update. The factory hands the migration plan the
    // device-state store's location for the watermark carry-over.
    let containers = try OttoContainerFactory.onDiskContainers(
        mainURL: url, deviceStateURL: deviceStateURL
    )
    return (OttoStore(containers: containers), containers)
}

/// A fresh pair of on-disk store URLs, cleaned up by the caller.
func storeURLs() -> (main: URL, deviceState: URL) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("otto-migration-\(UUID().uuidString)")
    return (
        base.appendingPathExtension("main.store"),
        base.appendingPathExtension("device.store")
    )
}
