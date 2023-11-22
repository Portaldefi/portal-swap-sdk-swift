import Promises

public protocol ILightningClient {
    func createInvoice(id: String, description: String, tokens: Int64) -> Promise<String>
    func subscribeToInvoice(id: String) -> Promise<InvoiceSubscription>
    func handleInvoiceUpdated(invoice: Invoice, party: Party)
    func decodePaymentRequest(request: [String:String]) -> Promise<Invoice>
    func payViaPaymentRequest(request: [String:String]) -> Promise<String>
    func settleInvoice(party: Party, secret: String) -> Promise<Void>
}
