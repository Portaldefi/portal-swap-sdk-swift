import BigInt

struct SwapRegisterdEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }

    let swapOwner: String
    let traderBuyId: BigUInt
    let sellAsset: String
    let sellAssetChainId: BigUInt
    let sellAmount: BigUInt
    let buyAsset: String
    let buyAssetChainId: BigUInt
    let poolFee: BigUInt
    let buyAmount: BigUInt
    let buyAmountSlippage: BigUInt
    let swapId: String
    let swapCreation: BigUInt

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataString = try container.decode(String.self, forKey: .data)
        
        func decodeAddress(from hexString: String) -> String {
            var hex = hexString
            if hex.hasPrefix("0x") {
                hex.removeFirst(2)
            }
            return "0x" + hex.suffix(40)
        }
        
        func decodeBigUInt(from hexString: String) -> BigUInt {
            return BigUInt(hexString, radix: 16) ?? BigUInt(0)
        }
        
        var dataSubstring = dataString.dropFirst(2) // Remove "0x" prefix

        let swapOwnerHex = String(dataSubstring.prefix(64))
        swapOwner = decodeAddress(from: swapOwnerHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let traderBuyIdHex = String(dataSubstring.prefix(64))
        traderBuyId = decodeBigUInt(from: traderBuyIdHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let sellAssetHex = String(dataSubstring.prefix(64))
        sellAsset = decodeAddress(from: sellAssetHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let sellAssetChainIdHex = String(dataSubstring.prefix(64))
        sellAssetChainId = decodeBigUInt(from: sellAssetChainIdHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let sellAmountHex = String(dataSubstring.prefix(64))
        sellAmount = decodeBigUInt(from: sellAmountHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let buyAssetHex = String(dataSubstring.prefix(64))
        buyAsset = decodeAddress(from: buyAssetHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let buyAssetChainIdHex = String(dataSubstring.prefix(64))
        buyAssetChainId = decodeBigUInt(from: buyAssetChainIdHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let poolFeeHex = String(dataSubstring.prefix(64))
        poolFee = decodeBigUInt(from: poolFeeHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let buyAmountHex = String(dataSubstring.prefix(64))
        buyAmount = decodeBigUInt(from: buyAmountHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let buyAmountSlippageHex = String(dataSubstring.prefix(64))
        buyAmountSlippage = decodeBigUInt(from: buyAmountSlippageHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let swapIdHex = String(dataSubstring.prefix(64))
        swapId = "0x" + swapIdHex
        dataSubstring = dataSubstring.dropFirst(64)
        
        let swapCreationHex = String(dataSubstring.prefix(64))
        swapCreation = decodeBigUInt(from: swapCreationHex)
    }

    public func encode(to encoder: Encoder) throws {}
}
