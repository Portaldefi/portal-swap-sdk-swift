import Web3

public struct AssetPair {
    public struct Asset {
        public let nativeAddress: EthereumAddress
        public let portalAddress: EthereumAddress
        public let decimals: UInt8
        public let minOrderSize: BigUInt
        public let maxOrderSize: BigUInt
        public let unit: String
        public let multiplier: UInt64
        public let chainId: UInt32
        public let deleted: Bool
        public let name: String
        public let logo: String
        public let chainName: String
        public let symbol: String
    }
    
    public let base: Asset
    public let quote: Asset
}
