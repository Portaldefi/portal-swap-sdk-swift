import Foundation
import Promises
import Web3

struct AmmSwap: Codable {
    let swapId: Data
    let secretHash: Data
    let liquidityPoolId: Data
    let sellAsset: EthereumAddress
    let sellAmount: BigUInt
    let buyAsset: EthereumAddress
    let buyAmount: BigUInt
    let slippage: BigUInt
    let swapCreation: BigUInt
    let swapOwner: EthereumAddress
    let buyId: String
    let status: String
    
    init(record: DBAmmSwap) {
        swapId = Data(hex: record.swapId!)
        secretHash = Data(hex: record.secretHash!)
        liquidityPoolId = Data(hex: record.secretHash!)
        sellAsset = EthereumAddress(hexString: record.sellerAddress!)!
        sellAmount = BigUInt(stringLiteral: record.sellAmount!)
        buyAsset = EthereumAddress(hexString: record.buyAsset!)!
        buyAmount = BigUInt(stringLiteral: record.buyAmount!)
        slippage = BigUInt(stringLiteral: record.buyAmountSlippage!)
        swapCreation = BigUInt(stringLiteral: record.tsCreation!)
        swapOwner = EthereumAddress(hexString: record.buyAsset!)!
        buyId = record.status!
        status = record.status!
    }
    
    init(swapId: Data, secretHash: Data, liquidityPoolId: Data, sellAsset: EthereumAddress, sellAmount: BigUInt, buyAsset: EthereumAddress, buyAmount: BigUInt, slippage: BigUInt, swapCreation: BigUInt, swapOwner: EthereumAddress, buyId: String, status: String) {
        self.swapId = swapId
        self.secretHash = secretHash
        self.liquidityPoolId = liquidityPoolId
        self.sellAsset = sellAsset
        self.sellAmount = sellAmount
        self.buyAsset = buyAsset
        self.buyAmount = buyAmount
        self.slippage = slippage
        self.swapCreation = swapCreation
        self.swapOwner = swapOwner
        self.buyId = buyId
        self.status = status
    }
}

extension AmmSwap {
    func toJSON() -> [String: Any] {
        Utils.convertToJSON(self) ?? [:]
    }
    
    static func from(json: [String: Any]) throws -> AmmSwap {
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        return try JSONDecoder().decode(AmmSwap.self, from: jsonData)
    }
}
