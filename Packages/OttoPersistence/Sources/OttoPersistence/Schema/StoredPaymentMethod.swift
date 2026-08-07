import Foundation
import SwiftData

extension OttoSchemaV1 {
    /// Persistence record for `PaymentMethod` (spec §5.5). Subscriptions reference
    /// it by scalar `paymentMethodID`, matching the domain - no relationship.
    @Model
    final class StoredPaymentMethod {
        var id: UUID?
        var label: String?
        var last4: String?
        var issuer: String?
        var expiryMonth: Int?
        var expiryYear: Int?
        var isDefault: Bool = false
        var deletedAt: Date?

        init() {}
    }
}
