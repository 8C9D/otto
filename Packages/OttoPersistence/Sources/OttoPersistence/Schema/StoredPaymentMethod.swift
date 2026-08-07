import Foundation
import SwiftData

extension OttoSchemaV2 {
    /// Persistence record for `PaymentMethod` (spec §5.5). Subscriptions reference
    /// it by scalar `paymentMethodID`, matching the domain - no relationship, and
    /// a dangling id is a valid state that renders as "Unknown payment method"
    /// (spec §3.5): under sync a subscription can arrive before its card.
    @Model
    final class StoredPaymentMethod {
        var id: UUID?
        var label: String?
        var last4: String?
        var issuer: String?
        var expiryMonth: Int?
        var expiryYear: Int?
        var isDefault: Bool = false
        var createdAt: Date?
        var updatedAt: Date?
        var deletedAt: Date?

        init() {}
    }
}
