import Foundation
import Web3

public struct SwapOrder {
    public let poolId: String
    public let buyAsset: String
    public let buyNetwork: String
    public let buyAddress: String
    public let buyAmount: BigUInt
    public let sellAsset: String
    public let sellNetwork: String
    public let sellAddress: String
    public let sellAmount: BigUInt
    
    public init(poolId: String, buyAsset: String, buyNetwork: String, buyAddress: String, buyAmount: BigUInt, sellAsset: String, sellNetwork: String, sellAddress: String, sellAmount: BigUInt) {
        self.poolId = poolId
        self.buyAsset = buyAsset
        self.buyNetwork = buyNetwork
        self.buyAddress = buyAddress
        self.buyAmount = buyAmount
        self.sellAsset = sellAsset
        self.sellNetwork = sellNetwork
        self.sellAddress = sellAddress
        self.sellAmount = sellAmount
    }
}
