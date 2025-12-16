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
    var metadata: String?
    
    func isSecretSeeker() throws -> Bool {
        guard let swap else {
            throw SwapSDKError.msg("Party missing swap")
        }
        
        return self == swap.secretSeeker
    }
    
    func isSecretHolder() throws -> Bool {
        guard let swap else {
            throw SwapSDKError.msg("Party missing swap")
        }
        
        return self == swap.secretHolder
    }
    
    func secretHashBytes() throws -> Data {
        guard let swap else {
            throw SwapSDKError.msg("Party missing swap")
        }
        return Data(hex: swap.secretHash)
    }
    
    init(swap: Swap? = nil, portalAddress: EthereumAddress, amount: BigUInt, chain: String, symbol: String, contractAddress: String, invoice: Invoice? = nil, receipt: Receipt? = nil, metadata: String? = nil) {
        self.swap = swap
        self.portalAddress = portalAddress
        self.amount = amount
        self.chain = chain
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.invoice = invoice
        self.receipt = receipt
        self.metadata = metadata
    }
}

extension Party: Equatable {
    static func == (lhs: Party, rhs: Party) -> Bool {
        lhs.portalAddress == rhs.portalAddress
        && lhs.amount == rhs.amount
        && lhs.chain == rhs.chain
        && lhs.symbol == rhs.symbol
        && lhs.contractAddress == rhs.contractAddress
    }
}
