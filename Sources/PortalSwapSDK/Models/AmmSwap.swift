import Foundation
import Promises
import Web3

public struct AmmSwap: Codable {
    public let swapId: Data
    public let secretHash: Data
    public let liquidityPoolId: Data
    public let sellAssetSymbol: String
    public let sellAsset: EthereumAddress
    public let sellAmount: BigUInt
    public let buyAssetSymbol: String
    public let buyAsset: EthereumAddress
    public let buyAmount: BigUInt
    public let slippage: BigUInt
    public let swapCreation: BigUInt
    public let swapOwner: EthereumAddress
    public let buyId: String
    public let status: String
    
    public init(record: DBAmmSwap) {
        swapId = Data(hex: record.swapId!)
        secretHash = Data(hex: record.secretHash!)
        liquidityPoolId = Data(hex: record.liquidityPoolId!)
        sellAssetSymbol = record.sellAssetSymbol ?? ""
        sellAsset = EthereumAddress(hexString: record.sellAsset!)!
        sellAmount = BigUInt(stringLiteral: record.sellAmount!)
        buyAssetSymbol = record.buyAssetSymbol ?? ""
        buyAsset = EthereumAddress(hexString: record.buyAsset!)!
        buyAmount = BigUInt(stringLiteral: record.buyAmount!)
        slippage = BigUInt(stringLiteral: record.slippage ?? "0")
        swapCreation = BigUInt(stringLiteral: record.swapCreation ?? "0")
        swapOwner = EthereumAddress(hexString: record.swapOwner!)!
        buyId = record.buyId ?? "0"
        status = record.status ?? "unknown"
    }
    
    init(swapId: Data, secretHash: Data, liquidityPoolId: Data, sellAssetSymbol: String, sellAsset: EthereumAddress, sellAmount: BigUInt, buyAssetSymbol: String, buyAsset: EthereumAddress, buyAmount: BigUInt, slippage: BigUInt, swapCreation: BigUInt, swapOwner: EthereumAddress, buyId: String, status: String) {
        self.swapId = swapId
        self.secretHash = secretHash
        self.liquidityPoolId = liquidityPoolId
        self.sellAssetSymbol = sellAssetSymbol
        self.sellAsset = sellAsset
        self.sellAmount = sellAmount
        self.buyAssetSymbol = buyAssetSymbol
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
