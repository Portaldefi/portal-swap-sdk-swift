import Foundation
import Promises
import Web3

typealias Invoice = [String: String]
typealias Response = [String: String]

protocol IBlockchain: BaseClass {
    func create(invoice: Invoice) -> Promise<Response>
    func settle(invoice: Invoice, secret: Data) -> Promise<Response>
}
