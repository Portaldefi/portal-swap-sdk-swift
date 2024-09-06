import Foundation

public class InvoiceSubscription {
    public enum Status {
        case awaitsPayment, paymentHeld, paymentConfirmed(String?), paymentCanceled
    }
    
    public var status: Status = .awaitsPayment
    
    public var onInvoiceUpdated: ((Status) -> Void)?
    
    public init(onInvoiceUpdated: ( (Status) -> Void)? = nil) {
        self.onInvoiceUpdated = onInvoiceUpdated
    }
    
    public func update(status: Status) {
        self.status = status
        onInvoiceUpdated?(status)
    }
    
    public func off(_ str: String) {
        onInvoiceUpdated = nil
    }
}
