import Promises

public protocol IBlockchain: BaseClass {
    func connect() -> Promise<Void>
    func disconnect() -> Promise<Void>
    func createInvoice(party: Party) -> Promise<[String: String]>
    func payInvoice(party: Party) -> Promise<Void>
    func settleInvoice(party: Party, secret: String) -> Promise<[String: String]>
}
