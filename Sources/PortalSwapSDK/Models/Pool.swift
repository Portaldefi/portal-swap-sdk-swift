import Foundation
import Web3

public struct Pool: Identifiable {
    public struct Asset: Identifiable, Hashable {
        public let id: EthereumAddress
        public let name: String
        public let symbol: String
        public let logo: String
        public let blockchainId: BigUInt
        public let blockchainName: String
        public let blockchainAddress: String
        public let blockchainDecimals: UInt8
    }
    
    public let id: String
    public let baseAsset: Asset
    public let quoteAsset: Asset
    public let fee: BigUInt
    public let minOrderSize: BigUInt
    public let maxOrderSize: BigUInt
    
    init(model: PoolModel, baseAsset: Asset, quoteAsset: Asset) {
        self.id = model.id.hexString
        self.baseAsset = baseAsset
        self.quoteAsset = quoteAsset
        self.fee = model.fee
        self.minOrderSize = model.minOrderSize
        self.maxOrderSize = model.maxOrderSize
    }
}
