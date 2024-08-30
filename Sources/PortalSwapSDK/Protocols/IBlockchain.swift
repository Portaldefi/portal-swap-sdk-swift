import Foundation
import Promises
import Web3

protocol IBlockchain: BaseClass {
    func connect() -> Promise<Void>
    func disconnect() -> Promise<Void>
    func create(invoice: [String: String]) -> Promise<[String: String]>
    func settle(invoice: [String: String], secret: Data) -> Promise<[String: String]>
}
