import BigInt
import Foundation
import Web3
import Web3ContractABI

final class Party {
    let portalAddress: EthereumAddress
    let amount: BigUInt
    let chain: String
    let symbol: String
    let contractAddress: String
    
    weak var swap: Swap?
    var invoice: Invoice?
    var receipt: Receipt?
    
    init(swap: Swap? = nil, portalAddress: EthereumAddress, amount: BigUInt, chain: String, symbol: String, contractAddress: String, invoice: Invoice? = nil, receipt: Receipt? = nil) {
        self.swap = swap
        self.portalAddress = portalAddress
        self.amount = amount
        self.chain = chain
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.invoice = invoice
        self.receipt = receipt
    }
}
