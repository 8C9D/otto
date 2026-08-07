import Foundation
import Observation
import OttoDomain

/// The Add/Edit form for a payment method (spec §5.5). Deliberately cheap to
/// fill: a label plus last4 is enough, because the inline path from the
/// subscription form must not turn entry into a project - entry abandonment is
/// the failure mode that makes the whole app moot.
@MainActor
@Observable
public final class PaymentMethodFormModel {

    public var label: String
    public var last4: String
    public var issuer: String
    public var expiryMonth: Int
    public var expiryYear: Int
    public var isDefault: Bool

    /// The method being edited, or nil when adding.
    public let original: PaymentMethod?
    private let newID: UUID
    private let dates: DateProvider

    /// A blank form. The expiry defaults three years out - a typical card
    /// lifetime - so an unedited default is plausible rather than instantly
    /// warning.
    public init(dates: DateProvider = .live) {
        let today = dates.today()
        self.original = nil
        self.newID = UUID()
        self.dates = dates
        self.label = ""
        self.last4 = ""
        self.issuer = ""
        self.expiryMonth = today.month
        self.expiryYear = today.year + 3
        self.isDefault = false
    }

    public init(editing method: PaymentMethod, dates: DateProvider = .live) {
        self.original = method
        self.newID = method.id
        self.dates = dates
        self.label = method.label
        self.last4 = method.last4
        self.issuer = method.issuer
        self.expiryMonth = method.expiryMonth
        self.expiryYear = method.expiryYear
        self.isDefault = method.isDefault
    }

    /// The label the card gets when the user typed issuer and digits but no
    /// label - "Bank ••4821" - so the cheap path still yields a readable list.
    public var suggestedLabel: String? {
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmedLast4
        switch (trimmedIssuer.isEmpty, digits.isEmpty) {
        case (false, false): return "\(trimmedIssuer) ••\(digits)"
        case (false, true): return trimmedIssuer
        case (true, false): return "••\(digits)"
        case (true, true): return nil
        }
    }

    private var trimmedLast4: String {
        last4.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Valid when it identifies the card at all (a label, an issuer, or the
    /// digits) and last4, if given, is exactly four digits.
    public var canSave: Bool {
        buildPaymentMethod() != nil
    }

    public func buildPaymentMethod() -> PaymentMethod? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedLabel = trimmedLabel.isEmpty ? suggestedLabel : trimmedLabel else {
            return nil
        }
        let digits = trimmedLast4
        guard digits.isEmpty || (digits.count == 4 && digits.allSatisfy(\.isNumber)) else {
            return nil
        }
        guard (1...12).contains(expiryMonth), expiryYear >= 2000 else { return nil }
        let now = dates.now()
        return PaymentMethod(
            id: newID,
            label: resolvedLabel,
            last4: digits,
            issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines),
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            isDefault: isDefault,
            createdAt: original?.createdAt ?? now,
            updatedAt: now
        )
    }
}
