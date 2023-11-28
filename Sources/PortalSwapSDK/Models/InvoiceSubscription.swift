public class InvoiceSubscription {
    public var onInvoiceUpdated: ((HodlInvoice.Status) -> Void)?
    
    public init(onInvoiceUpdated: ( (HodlInvoice.Status) -> Void)? = nil) {
        self.onInvoiceUpdated = onInvoiceUpdated
    }
    
    public func off(_ str: String) {
        onInvoiceUpdated = nil
    }
}
