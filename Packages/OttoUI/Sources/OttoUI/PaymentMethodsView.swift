import SwiftUI
import OttoDomain
import OttoStores

/// Payment methods (spec §5.5, §7.1 screen 8): the cards, their expiry
/// warnings, and what each one carries per month. Wave 3's picker hid itself
/// because nothing could create a `PaymentMethod`; this screen gives it objects.
struct PaymentMethodsView: View {
    @Environment(AppModel.self) private var model
    @State private var editingMethod: PaymentMethod?
    @State private var isAdding = false
    @State private var actionFailure: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Payment methods"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAdding = true
                        } label: {
                            Label(String(localized: "Add a card"), systemImage: "plus")
                        }
                    }
                }
        }
        .task {
            await model.paymentMethodsStore.refresh()
            // The per-card totals come from the subscriptions themselves.
            await model.subscriptionsStore.refresh()
        }
        .sheet(isPresented: $isAdding) {
            PaymentMethodFormView(form: model.paymentMethodFormModel())
        }
        .sheet(item: $editingMethod) { method in
            PaymentMethodFormView(form: model.paymentMethodFormModel(editing: method))
        }
        .alert(
            String(localized: "Something went wrong"),
            isPresented: Binding(
                get: { actionFailure != nil },
                set: { if !$0 { actionFailure = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(actionFailure ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        let store = model.paymentMethodsStore
        switch store.state {
        case .loading:
            ProgressView(String(localized: "Loading…"))
        case .failed(let error):
            LoadFailedView(error: error) { await store.refresh() }
        case .loaded(let methods) where methods.isEmpty:
            ContentUnavailableView(
                String(localized: "No cards yet"),
                systemImage: "wallet.pass",
                description: Text(String(localized: """
                Add the cards your subscriptions bill to and Otto shows what \
                each one carries - and warns before one expires.
                """))
            )
        case .loaded(let methods):
            methodsList(methods)
        }
    }

    private func methodsList(_ methods: [PaymentMethod]) -> some View {
        let today = model.subscriptionsStore.today
        let loads = paymentMethodLoads(
            subscriptions: model.subscriptionsStore.subscriptions.value ?? [], asOf: today
        )
        return List {
            ForEach(methods) { method in
                Button {
                    editingMethod = method
                } label: {
                    PaymentMethodRow(
                        method: method,
                        load: loads[method.id],
                        currencyCode: currencyCode,
                        today: today
                    )
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for offset in offsets {
                    let method = methods[offset]
                    Task {
                        do {
                            try await model.paymentMethodsStore.delete(paymentMethodID: method.id)
                        } catch {
                            actionFailure = error.localizedDescription
                        }
                    }
                }
            }
        }
        .refreshable {
            await model.paymentMethodsStore.refresh()
            await model.subscriptionsStore.refresh()
        }
    }

    private var currencyCode: String {
        model.subscriptionsStore.subscriptions.value?.first?.currencyCode ?? "CAD"
    }
}

/// One card: label, expiry (warned when close, loud when past), and the slice
/// of the monthly burn it carries.
struct PaymentMethodRow: View {
    let method: PaymentMethod
    let load: PaymentMethodLoad?
    let currencyCode: String
    let today: CalendarDay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(method.label)
                    .font(.headline)
                if method.isDefault {
                    Text(String(localized: "Default"))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if let load {
                    Text(String(localized: "\(currencyText(cents: load.monthlyCents, currencyCode: currencyCode))/mo"))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            expiryLabel
                .font(.subheadline)
            if let load {
                // "Billed", not "bill(s)": the inflection engine pluralizes
                // the noun but does not conjugate English verbs (Wave 10,
                // defect I), so the copy stays number-invariant around it.
                Text(String(localized: "\(subscriptionCountText(load.subscriptionCount)) billed to this card"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Nothing bills to this card"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Expiry states carry their meaning in words and symbol, never colour
    /// alone (Wave 3 accessibility constraint).
    @ViewBuilder
    private var expiryLabel: some View {
        let expiry = String(format: "%02d/%d", method.expiryMonth, method.expiryYear)
        switch method.expiryStatus(asOf: today) {
        case .valid:
            Text(String(localized: "Expires \(expiry)"))
                .foregroundStyle(.secondary)
        case .expiringSoon(let lastValidDay):
            Label(
                String(localized: "Expires \(lastValidDay.displayText()) - update it with your vendors"),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        case .expired(let lastValidDay):
            Label(
                String(localized: "Expired \(lastValidDay.displayText())"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
        }
    }
}

/// The add/edit form (spec §5.5), shared by the management screen and the
/// inline path from the subscription form. `onSaved` hands the saved method
/// back so the inline path can select it in the picker immediately.
struct PaymentMethodFormView: View {
    @State var form: PaymentMethodFormModel
    var onSaved: ((PaymentMethod) -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Label"), text: $form.label, prompt: labelPrompt)
                    TextField(String(localized: "Issuer - Bank, Amex…"), text: $form.issuer)
                    TextField(String(localized: "Last 4 digits"), text: $form.last4)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    Text(String(localized: "A label or the issuer and digits is enough."))
                }
                Section(String(localized: "Expiry")) {
                    Picker(String(localized: "Month"), selection: $form.expiryMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(String(format: "%02d", month)).tag(month)
                        }
                    }
                    Picker(String(localized: "Year"), selection: $form.expiryYear) {
                        ForEach(yearOptions, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                }
                Section {
                    Toggle(String(localized: "Default card"), isOn: $form.isDefault)
                } footer: {
                    Text(String(localized: "New subscriptions suggest the default card first."))
                }
            }
            .navigationTitle(
                form.original == nil
                    ? String(localized: "New card")
                    : String(localized: "Edit card")
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
                String(localized: "Couldn't save the card"),
                isPresented: Binding(
                    get: { failure != nil },
                    set: { if !$0 { failure = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private var labelPrompt: Text? {
        form.suggestedLabel.map { Text($0) }
    }

    /// The expiry year picker spans this year through fifteen out - past years
    /// only appear when editing a card that already expired.
    private var yearOptions: [Int] {
        let current = model.subscriptionsStore.today.year
        let earliest = min(current, form.expiryYear)
        return Array(earliest...(current + 15))
    }

    private func save() async {
        guard let method = form.buildPaymentMethod() else { return }
        do {
            try await model.paymentMethodsStore.save(method)
            onSaved?(method)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
