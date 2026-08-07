import SwiftUI
import OttoDomain
import OttoStores

/// Add/Edit (spec §7.1 item 3) - the screen that decides whether the app gets
/// used. Both §5.1 entry modes sit in one segmented control, equally prominent;
/// every derived date renders live as the user types, and the user is never asked
/// to compute one.
struct AddEditSubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var form: SubscriptionFormModel
    @State private var saveFailure: String?

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(
                    form.original == nil
                        ? String(localized: "New Subscription")
                        : String(localized: "Edit Subscription")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save")) {
                            Task { await save() }
                        }
                        .disabled(!form.canSave)
                    }
                }
                .alert(
                    String(localized: "Couldn't save"),
                    isPresented: Binding(
                        get: { saveFailure != nil },
                        set: { if !$0 { saveFailure = nil } }
                    )
                ) {
                    Button(String(localized: "OK"), role: .cancel) {}
                } message: {
                    Text(saveFailure ?? "")
                }
        }
        .task { await model.paymentMethodsStore.refresh() }
    }

    private var formContent: some View {
        @Bindable var form = form
        return Form {
            Section {
                TextField(String(localized: "Name"), text: $form.name)
                Picker(String(localized: "Category"), selection: $form.category) {
                    ForEach(OttoDomain.Category.allCases, id: \.self) { category in
                        Text(categoryText(category)).tag(category)
                    }
                }
            }

            Section(String(localized: "Price")) {
                TextField(
                    String(localized: "Price"),
                    value: $form.amount,
                    format: .currency(code: form.original?.currencyCode ?? "CAD")
                )
                .decimalKeyboard()
                .accessibilityLabel(String(localized: "Price"))
                Picker(String(localized: "Billing cycle"), selection: $form.cyclePreset) {
                    ForEach(SubscriptionFormModel.CyclePreset.allCases, id: \.self) { preset in
                        Text(presetText(preset)).tag(preset)
                    }
                }
                if form.cyclePreset == .everyNDays {
                    Stepper(value: $form.customCycleDays, in: 1...365) {
                        LabeledContent(
                            String(localized: "Every"),
                            value: String(localized: "\(form.customCycleDays) days")
                        )
                    }
                }
            }

            billingDateSection($form)
            trialSection($form)

            Section(String(localized: "Reminders")) {
                Stepper(value: $form.reminderLeadDays, in: 0...30) {
                    LabeledContent(
                        String(localized: "Remind me"),
                        value: String(localized: "\(form.reminderLeadDays) days before")
                    )
                }
                Toggle(String(localized: "Also remind on the day"), isOn: $form.sameDayReminder)
            }

            paymentSection($form)

            Section(String(localized: "Cancelling, for later")) {
                TextField(String(localized: "Cancellation link"), text: $form.cancellationURLText)
                    .urlKeyboard()
                TextField(
                    String(localized: "How to cancel (phone number, steps…)"),
                    text: $form.cancellationNotes,
                    axis: .vertical
                )
            }

            Section(String(localized: "Notes")) {
                TextField(String(localized: "Account page link"), text: $form.vendorURLText)
                    .urlKeyboard()
                TextField(String(localized: "Notes"), text: $form.notes, axis: .vertical)
            }
        }
    }

    // MARK: - Billing date

    private func billingDateSection(_ form: Bindable<SubscriptionFormModel>) -> some View {
        Section {
            Picker(String(localized: "What do you know?"), selection: form.entryMode) {
                Text(String(localized: "When it started"))
                    .tag(SubscriptionFormModel.EntryMode.startDate)
                Text(String(localized: "My next charge"))
                    .tag(SubscriptionFormModel.EntryMode.nextCharge)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "How do you want to enter the billing date?"))

            switch self.form.entryMode {
            case .startDate:
                DatePicker(
                    String(localized: "Started on"),
                    selection: form.startDate.asDate(),
                    displayedComponents: .date
                )
                if let next = self.form.computedNextBillingDate {
                    LabeledContent(String(localized: "Next charge"), value: next.displayText())
                        .accessibilityLabel(String(localized: "Next charge \(next.displayText())"))
                }
            case .nextCharge:
                DatePicker(
                    String(localized: "Next charge on"),
                    selection: form.nextChargeDate.asDate(),
                    displayedComponents: .date
                )
                lastDayQuestion(form)
            }
        } header: {
            Text(String(localized: "Billing date"))
        } footer: {
            if self.form.entryMode == .nextCharge {
                Text(String(localized: "Don't know when it started? The next charge date is all Otto needs."))
            }
        }
    }

    /// Spec §5.1's one-tap disambiguation, shown only when the entered date is
    /// genuinely ambiguous.
    @ViewBuilder
    private func lastDayQuestion(_ form: Bindable<SubscriptionFormModel>) -> some View {
        if self.form.lastDayAnchorCandidate != nil {
            Picker(
                String(localized: "Is this the last day of the month, or specifically the \(dayOrdinal)?"),
                selection: form.lastDayAnswer
            ) {
                Text(String(localized: "Not sure yet"))
                    .tag(SubscriptionFormModel.LastDayAnswer?.none)
                Text(String(localized: "Last day of the month"))
                    .tag(SubscriptionFormModel.LastDayAnswer?.some(.lastDayOfMonth))
                Text(String(localized: "The \(dayOrdinal)"))
                    .tag(SubscriptionFormModel.LastDayAnswer?.some(.enteredDay))
            }
            .pickerStyle(.inline)
        }
    }

    private var dayOrdinal: String {
        let dayNumber = self.form.nextChargeDate.day
        return "\(dayNumber)\(ordinalSuffix(dayNumber))"
    }

    // MARK: - Trial

    private func trialSection(_ form: Bindable<SubscriptionFormModel>) -> some View {
        Section {
            Toggle(String(localized: "This is a free trial"), isOn: form.isTrial)
            if self.form.isTrial {
                DatePicker(
                    String(localized: "Trial started"),
                    selection: form.trialStartDate.asDate(),
                    displayedComponents: .date
                )
                Stepper(value: form.trialLengthDays, in: 1...365) {
                    LabeledContent(
                        String(localized: "Length"),
                        value: String(localized: "\(self.form.trialLengthDays) days")
                    )
                }
                Stepper(value: form.trialBufferDays, in: 0...30) {
                    LabeledContent(
                        String(localized: "Safety buffer"),
                        value: String(localized: "\(self.form.trialBufferDays) days")
                    )
                }
                if let conversion = self.form.trialConversionDate, let cancelBy = self.form.trialCancelByDate {
                    LabeledContent(String(localized: "Converts to paid"), value: conversion.displayText())
                        .accessibilityLabel(String(localized: "Converts to paid \(conversion.displayText())"))
                    LabeledContent(String(localized: "Cancel by"), value: cancelBy.displayText())
                        .fontWeight(.medium)
                        .accessibilityLabel(String(localized: "Cancel by \(cancelBy.displayText())"))
                }
            }
        } header: {
            Text(String(localized: "Free trial"))
        } footer: {
            if self.form.isTrial {
                Text(String(localized: "Otto works out the dates - the price above is what it charges after the trial."))
            }
        }
    }

    // MARK: - Payment method

    @ViewBuilder
    private func paymentSection(_ form: Bindable<SubscriptionFormModel>) -> some View {
        // Wave 7 owns managing payment methods; until then the picker only
        // appears when some already exist.
        if let methods = model.paymentMethodsStore.state.value, !methods.isEmpty {
            Section(String(localized: "Payment method")) {
                Picker(String(localized: "Paid with"), selection: form.paymentMethodID) {
                    Text(String(localized: "None")).tag(UUID?.none)
                    ForEach(methods) { method in
                        Text(method.label).tag(UUID?.some(method.id))
                    }
                }
            }
        }
    }

    // MARK: - Saving

    private func save() async {
        guard let subscription = form.buildSubscription() else { return }
        do {
            try await model.subscriptionsStore.save(subscription)
            dismiss()
        } catch {
            saveFailure = error.localizedDescription
        }
    }
}

// MARK: - Small helpers

private let categoryNames: [OttoDomain.Category: String] = [
    .streamingAndVideo: String(localized: "Streaming & Video"),
    .musicAndAudio: String(localized: "Music & Audio"),
    .newsAndReading: String(localized: "News & Reading"),
    .aiAndSoftwareTools: String(localized: "AI & Software Tools"),
    .cloudAndStorage: String(localized: "Cloud & Storage"),
    .gaming: String(localized: "Gaming"),
    .fitnessAndHealth: String(localized: "Fitness & Health"),
    .foodAndDelivery: String(localized: "Food & Delivery"),
    .shoppingAndMemberships: String(localized: "Shopping & Memberships"),
    .phoneAndInternet: String(localized: "Phone & Internet"),
    .financeAndInsurance: String(localized: "Finance & Insurance"),
    .educationAndCourses: String(localized: "Education & Courses"),
    .other: String(localized: "Other")
]

func categoryText(_ category: OttoDomain.Category) -> String {
    // Every case is in the table; the raw value is a legible last resort, never
    // a silent blank.
    categoryNames[category] ?? category.rawValue
}

private func presetText(_ preset: SubscriptionFormModel.CyclePreset) -> String {
    switch preset {
    case .weekly: String(localized: "Weekly")
    case .biweekly: String(localized: "Biweekly")
    case .monthly: String(localized: "Monthly")
    case .quarterly: String(localized: "Quarterly")
    case .semiannual: String(localized: "Every 6 months")
    case .annual: String(localized: "Annual")
    case .everyNDays: String(localized: "Every … days")
    }
}

private func ordinalSuffix(_ number: Int) -> String {
    switch (number % 100, number % 10) {
    case (11...13, _): "th"
    case (_, 1): "st"
    case (_, 2): "nd"
    case (_, 3): "rd"
    default: "th"
    }
}

extension View {
    /// The decimal pad where it exists; a plain field elsewhere.
    func decimalKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.decimalPad)
        #else
        return self
        #endif
    }

    /// The URL keyboard where it exists.
    func urlKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        return autocorrectionDisabled()
        #endif
    }
}
