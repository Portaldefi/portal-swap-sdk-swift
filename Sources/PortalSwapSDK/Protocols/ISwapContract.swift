import Foundation
import Web3
import Web3ContractABI

public protocol ISwapContract: EthereumContract {
    static var InvoiceCreated: SolidityEvent { get }
    static var InvoicePaid: SolidityEvent { get }
    static var InvoiceSettled: SolidityEvent { get }

    func createInvoice(id: Data, swap: Data, asset: EthereumAddress, quantity: BigUInt) -> SolidityInvocation
    func payInvoice(id: Data, swap: Data, asset: EthereumAddress, quantity: BigUInt) -> SolidityInvocation
    func settleInvoice(secret: Data, swap: Data) -> SolidityInvocation
}
