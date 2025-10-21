import Foundation
import Promises
import Web3

public struct AmmSwap: Codable {
    public let swapId: Data
    public let swapTxHash: String?
    public let secretHash: Data
    public let sellAssetSymbol: String
    public let sellAsset: EthereumAddress
    public var sellAssetTx: String?
    public let sellAmount: BigUInt
    public let buyAssetSymbol: String
    public let buyAsset: EthereumAddress
    public let buyAssetTx: String?
    public let buyAmount: BigUInt
    public let swapCreation: BigUInt
    public let status: String
    
    public init(record: DBAmmSwap) {
        swapId = Data(hex: record.swapId!)
        
        secretHash = Data(hex: record.secretHash ?? String())
        
        status = record.status ?? "Unknown"
        
        swapTxHash = nil
        
        sellAsset = EthereumAddress(hexString: "0x443025f0adc5f1d03efcaf08432da53f39deadae")!
        sellAssetSymbol = "BTC"
        sellAmount = 0
        sellAssetTx = nil
        
        buyAsset = EthereumAddress(hexString: "0x443025f0adc5f1d03efcaf08432da53f39deadae")!
        buyAssetSymbol = "ETH"
        buyAmount = 0
        buyAssetTx = nil
        
        swapCreation = 0
    }
}

extension AmmSwap: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(swapId.hexString)
    }
    
    public static func == (lhs: AmmSwap, rhs: AmmSwap) -> Bool {
        return lhs.swapId == rhs.swapId
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
