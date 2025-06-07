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
        
        public init(id: EthereumAddress, name: String, symbol: String, logo: String, blockchainId: BigUInt, blockchainName: String, blockchainAddress: String, blockchainDecimals: UInt8) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.logo = logo
            self.blockchainId = blockchainId
            self.blockchainName = blockchainName
            self.blockchainAddress = blockchainAddress
            self.blockchainDecimals = blockchainDecimals
        }
    }
    
    public let id: String
    public let baseAsset: Asset
    public let quoteAsset: Asset
    public let minOrderSize: BigUInt
    public let maxOrderSize: BigUInt
    
    public init(id: String, baseAsset: Asset, quoteAsset: Asset, minOrderSize: BigUInt, maxOrderSize: BigUInt) {
        self.id = id
        self.baseAsset = baseAsset
        self.quoteAsset = quoteAsset
        self.minOrderSize = minOrderSize
        self.maxOrderSize = maxOrderSize
    }
}
