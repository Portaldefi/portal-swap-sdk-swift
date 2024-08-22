import Foundation
import Promises

protocol IBlockchain: BaseClass {
    func connect() -> Promise<Void>
    func disconnect() -> Promise<Void>
    func swapOrder(_ order: OrderRequest) -> Promise<[String: String]>
    func createInvoice(party: Party) -> Promise<[String: String]>
    func payInvoice(party: Party) -> Promise<[String: Any]>
    func settleInvoice(party: Party, secret: Data) -> Promise<[String: String]>
}
