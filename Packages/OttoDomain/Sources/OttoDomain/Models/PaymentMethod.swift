import Foundation

/// A payment card or account subscriptions bill against (spec §5.5). Card-expiry
/// warnings fall out of `expiryMonth`/`expiryYear` for free.
public struct PaymentMethod: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID

    /// Display label, e.g. "Bank Mastercard ..4821".
    public var label: String

    public var last4: String
    public var issuer: String
    public var expiryMonth: Int
    public var expiryYear: Int
    public var isDefault: Bool

    public init(
        id: UUID,
        label: String,
        last4: String,
        issuer: String,
        expiryMonth: Int,
        expiryYear: Int,
        isDefault: Bool
    ) {
        self.id = id
        self.label = label
        self.last4 = last4
        self.issuer = issuer
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.isDefault = isDefault
    }
}
