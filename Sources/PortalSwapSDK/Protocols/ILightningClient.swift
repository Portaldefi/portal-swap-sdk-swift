import Foundation
import Promises

public protocol ILightningClient {
    func createHodlInvoice(hash: String, memo: String, quantity: Int64) -> Promise<HodlInvoice>
    func subscribeToInvoice(id: String) -> Promise<InvoiceSubscription>
    func payViaPaymentRequest(swapId: String, request: String) -> Promise<PaymentResult>
    func settleHodlInvoice(secret: Data) -> Promise<[String:String]>
}
