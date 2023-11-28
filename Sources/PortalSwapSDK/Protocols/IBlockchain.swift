import Foundation
import Promises

public protocol IBlockchain: BaseClass {
    func connect() -> Promise<Void>
    func disconnect() -> Promise<Void>
    func createInvoice(party: Party) -> Promise<[String: String]>
    func payInvoice(party: Party) -> Promise<[String: Any]>
    func settleInvoice(party: Party, secret: Data) -> Promise<[String: String]>
}
