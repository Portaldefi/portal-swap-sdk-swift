import Foundation
import Promises
import BigInt

public protocol ILightningClient {
    typealias Response = [String: String]
    var publickKey: String { get }
    func createHodlInvoice(hash: String, memo: String, quantity: Int64) -> Promise<String>
    func subscribeToInvoice(id: String) -> Promise<InvoiceSubscription>
    func subscribeToPayment(id: String) -> Promise<InvoiceSubscription>
    func payViaPaymentRequest(swapId: String, request: String) -> Promise<PaymentResult>
    func payViaDetails(amountSat: BigInt, toNode: String, message: String) -> Promise<String>
    func settleHodlInvoice(secret: Data) -> Promise<Response>
}
