import Foundation

public class HodlInvoice {
    public enum Status {
        case awaitsPayment, paymentHeld, paymentConfirmed, paymentCanceled
    }
    
    public let id: String
    public let description: String
    public let tokens: UInt64
    public let paymentRequest: String
    
    public var subscription: InvoiceSubscription
    
    private var status: Status = .awaitsPayment
    
    public init(id: String, description: String, tokens: UInt64, paymentRequest: String) {
        self.id = id
        self.description = description
        self.tokens = tokens
        self.paymentRequest = paymentRequest
        self.subscription = InvoiceSubscription()
    }
    
    public func update(status: Status) {
        self.status = status
        subscription.onInvoiceUpdated?(status)
    }
}
