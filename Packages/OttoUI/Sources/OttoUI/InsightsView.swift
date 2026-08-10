import SwiftUI
import OttoDomain
import OttoStores

/// Insights (spec §7.2): burn, categories, the next twelve months, paused spend
/// as its own line, converting-soon trials with their consequence stated, the
/// zombie report, and the price-change log. Every number is computed in the
/// domain and loaded through the store; this view only renders.
struct InsightsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Insights"))
        }
        .task { await model.insightsStore.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        let store = model.insightsStore
        switch store.state {
        case .loading:
            ProgressView(String(localized: "Loading…"))
        case .failed(let error):
            LoadFailedView(error: error) { await store.refresh() }
        case .loaded(let data) where !data.hasSubscriptions:
            // Constraint 3: an empty database says something useful.
            ContentUnavailableView(
                String(localized: "Nothing to add up yet"),
                systemImage: "chart.bar",
                description: Text(String(localized: """
                Add subscriptions and Insights will show your monthly burn, \
                where it goes, and what's coming.
                """))
            )
        case .loaded(let data):
            insightsList(data)
        }
    }

    private func insightsList(_ data: InsightsData) -> some View {
        List {
            burnSection(data)
            convertingSoonSection(data)
            categorySection(data)
            next12MonthsSection(data)
            pausedSection(data)
            zombieSection(data)
            priceLogSection(data)
        }
        .refreshable { await model.insightsStore.refresh() }
    }

    // MARK: - Burn

    private func burnSection(_ data: InsightsData) -> some View {
        Section {
            LabeledContent(String(localized: "Monthly burn")) {
                Text(currencyText(cents: data.monthlyBurnCents, currencyCode: data.currencyCode))
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            LabeledContent(
                String(localized: "Annualized"),
                value: currencyText(cents: data.annualizedCents, currencyCode: data.currencyCode)
            )
        } footer: {
            if data.monthlyBurnCents == 0 {
                // Nothing active is still a fact worth stating plainly.
                Text(String(localized: "Nothing is actively billing right now."))
            } else {
                Text(String(localized: """
                All cycles normalised to months. Trials count once they convert; \
                paused spend is listed separately.
                """))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Converting soon

    @ViewBuilder
    private func convertingSoonSection(_ data: InsightsData) -> some View {
        if !data.convertingSoon.isEmpty {
            Section(String(localized: "Converting soon")) {
                ForEach(data.convertingSoon, id: \.subscription.id) { entry in
                    ConvertingTrialRow(entry: entry, currencyCode: data.currencyCode)
                }
            }
        }
    }

    // MARK: - Categories

    @ViewBuilder
    private func categorySection(_ data: InsightsData) -> some View {
        if !data.categories.isEmpty {
            Section(String(localized: "By category")) {
                ForEach(data.categories, id: \.category) { entry in
                    LabeledContent(categoryText(entry.category)) {
                        Text(currencyText(cents: entry.monthlyCents, currencyCode: data.currencyCode))
                            .font(.body.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Next 12 months

    private func next12MonthsSection(_ data: InsightsData) -> some View {
        Section {
            ForEach(data.next12Months, id: \.self) { month in
                LabeledContent(monthText(month)) {
                    Text(currencyText(cents: month.totalCents, currencyCode: data.currencyCode))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(isCluster(month, in: data) ? .primary : .secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(String(localized: "Next 12 months"))
        } footer: {
            Text(String(localized: "Where annual renewals cluster. The current month counts only what is still ahead."))
        }
    }

    /// A month that stands well above the typical month - the annual-renewal
    /// cluster §7.2 wants visible. Emphasis only; the number is always shown.
    private func isCluster(_ month: MonthlyProjection, in data: InsightsData) -> Bool {
        month.totalCents > data.monthlyBurnCents + data.monthlyBurnCents / 2 && month.totalCents > 0
    }

    private func monthText(_ month: MonthlyProjection) -> String {
        var components = DateComponents()
        components.year = month.year
        components.month = month.month
        components.day = 1
        // `MonthlyProjection`'s year and month are domain numbers, i.e.
        // proleptic Gregorian; resolving them through the device calendar
        // labels the projection 543 years out on a Buddhist device.
        guard let date = ottoDayCalendar.date(from: components) else {
            return "\(month.year)-\(month.month)"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Paused spend

    @ViewBuilder
    private func pausedSection(_ data: InsightsData) -> some View {
        if !data.pausedLines.isEmpty {
            Section {
                ForEach(data.pausedLines, id: \.subscription.id) { line in
                    LabeledContent {
                        Text(String(localized: "\(currencyText(cents: line.monthlyEquivalent, currencyCode: data.currencyCode))/mo"))
                            .font(.body.monospacedDigit())
                    } label: {
                        Text(line.subscription.name)
                        if line.subscription.pauseEndsOn == nil {
                            Text(String(localized: "Paused indefinitely"))
                        } else if let resumes = line.subscription.pauseEndsOn {
                            Text(String(localized: "Resumes \(resumes.displayText())"))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(String(localized: "Paused - not in your burn"))
            } footer: {
                Text(String(localized: "At the price frozen when the pause began. Price changes during a pause take effect at resume."))
            }
        }
    }

    // MARK: - Zombies

    @ViewBuilder
    private func zombieSection(_ data: InsightsData) -> some View {
        if !data.zombies.isEmpty {
            Section {
                ForEach(data.zombies, id: \.subscription.id) { entry in
                    NavigationLink {
                        SubscriptionDetailView(subscriptionID: entry.subscription.id)
                    } label: {
                        ZombieRow(entry: entry, currencyCode: data.currencyCode)
                    }
                }
            } header: {
                Text(String(localized: "No recorded use in 90+ days"))
            } footer: {
                Text(String(localized: """
                Recorded use only - Otto knows what you tell it, from the \
                check-in notifications or the subscription's screen.
                """))
            }
        }
    }

    // MARK: - Price log

    @ViewBuilder
    private func priceLogSection(_ data: InsightsData) -> some View {
        if !data.priceLog.isEmpty {
            Section(String(localized: "Price changes")) {
                ForEach(data.priceLog, id: \.change.id) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.subscriptionName)
                            Spacer()
                            Text(priceChangeText(entry))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(
                                    entry.change.newAmountCents > entry.change.oldAmountCents
                                        ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                                )
                        }
                        Text(priceChangeDetail(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func priceChangeText(_ entry: PriceChangeLogEntry) -> String {
        let old = currencyText(cents: entry.change.oldAmountCents, currencyCode: entry.currencyCode)
        let new = currencyText(cents: entry.change.newAmountCents, currencyCode: entry.currencyCode)
        return String(localized: "\(old) to \(new)")
    }

    private func priceChangeDetail(_ entry: PriceChangeLogEntry) -> String {
        let date = entry.change.effectiveDate.displayText()
        return switch entry.change.source {
        case .userEdit: String(localized: "\(date) - edited")
        case .chargeMismatch: String(localized: "\(date) - a charge differed")
        case .trialConversion: String(localized: "\(date) - trial converted")
        }
    }
}

/// One converting-soon line: the sentence that is the whole product in one line
/// (spec §7.2) - available before the money moves.
struct ConvertingTrialRow: View {
    let entry: ConvertingTrial
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.subscription.name)
                .font(.headline)
            Text(consequenceSentence)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private var consequenceSentence: String {
        // Cumulative: the second trial's "from" already includes the first's
        // conversion, so consecutive sentences chain instead of contradicting.
        let from = currencyText(
            cents: entry.burnAfterCents - entry.monthlyEquivalent, currencyCode: currencyCode
        )
        let raisedTo = currencyText(cents: entry.burnAfterCents, currencyCode: currencyCode)
        let date = entry.conversionDate.displayText()
        return String(localized: "Your monthly burn goes from \(from) to \(raisedTo) on \(date).")
    }
}

/// One zombie line: facts, never a recommendation (spec §7.3). What happened,
/// what it cost, and the annual number - the user decides.
struct ZombieRow: View {
    let entry: ZombieEntry
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.subscription.name)
                .font(.headline)
            Text(zombieSentence)
                .font(.subheadline)
            Text(String(localized: "About \(currencyText(cents: entry.annualCostCents, currencyCode: currencyCode)) a year."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var zombieSentence: String {
        let name = entry.subscription.name
        let cost = currencyText(cents: entry.costSinceCents, currencyCode: currencyCode)
        if let lastUsed = entry.lastUsedDate {
            let since = lastUsed.displayText()
            return String(localized: "You haven't recorded using \(name) since \(since). It has cost you \(cost) since then.")
        }
        return String(localized: "You've never recorded using \(name). It has cost you \(cost) so far.")
    }
}
