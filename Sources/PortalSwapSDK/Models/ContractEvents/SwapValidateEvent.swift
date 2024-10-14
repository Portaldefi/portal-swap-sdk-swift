import BigInt
import Foundation

struct SwapValidatedEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }
    
    let swapId: String
    let liquidityPoolId: String
    let secretHash: String
    let sellAsset: String
    let sellAmount: BigUInt
    let buyAsset: String
    let buyAmount: BigUInt
    let slippage: BigUInt
    let swapCreation: BigUInt
    let swapOwner: String
    let buyId: String
    let status: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataString = try container.decode(String.self, forKey: .data)
        
        let dataSubstring = dataString.dropFirst(2) // Remove "0x" prefix
        
        func decodeAddress(from hexString: String) -> String {
            return "0x" + hexString.suffix(40)
        }
        
        func decodeBigUInt(from hexString: String) -> BigUInt {
            return BigUInt(hexString, radix: 16) ?? BigUInt(0)
        }
        
        func decodeBytes32(from hexString: String) -> String {
            return "0x" + hexString
        }
        
        // Extract and decode each parameter
        let idHex = String(dataSubstring.prefix(64))
        swapId = decodeBytes32(from: idHex)
        
        let remainingData1 = dataSubstring.dropFirst(64)
        let liquidityPoolIdHex = String(remainingData1.prefix(64))
        liquidityPoolId = decodeBytes32(from: liquidityPoolIdHex)
        
        let remainingData2 = remainingData1.dropFirst(64)
        let secretHashHex = String(remainingData2.prefix(64))
        secretHash = decodeBytes32(from: secretHashHex)
        
        let remainingData3 = remainingData2.dropFirst(64)
        let sellAssetHex = String(remainingData3.prefix(64))
        sellAsset = decodeAddress(from: sellAssetHex)
        
        let remainingData4 = remainingData3.dropFirst(64)
        let sellAmountHex = String(remainingData4.prefix(64))
        sellAmount = decodeBigUInt(from: sellAmountHex)
        
        let remainingData5 = remainingData4.dropFirst(64)
        let buyAssetHex = String(remainingData5.prefix(64))
        buyAsset = decodeAddress(from: buyAssetHex)
        
        let remainingData6 = remainingData5.dropFirst(64)
        let buyAmountHex = String(remainingData6.prefix(64))
        buyAmount = decodeBigUInt(from: buyAmountHex)
        
        let remainingData7 = remainingData6.dropFirst(64)
        let slippageHex = String(remainingData7.prefix(64))
        slippage = decodeBigUInt(from: slippageHex)
        
        let remainingData8 = remainingData7.dropFirst(64)
        let swapCreationHex = String(remainingData8.prefix(64))
        swapCreation = decodeBigUInt(from: swapCreationHex)
        
        let remainingData9 = remainingData8.dropFirst(64)
        let swapOwnerHex = String(remainingData9.prefix(64))
        swapOwner = decodeAddress(from: swapOwnerHex)
        
        let remainingData10 = remainingData9.dropFirst(64)
        let buyIdHex = String(remainingData10.prefix(64))
        buyId = decodeBytes32(from: buyIdHex)
        
        let remainingData11 = remainingData10.dropFirst(64)
        let statusHex = String(remainingData11.prefix(64))
        status = decodeBytes32(from: statusHex)
    }
    
    init(swapId: String, liquidityPoolId: String, secretHash: String, sellAsset: String, sellAmount: BigUInt, buyAsset: String, buyAmount: BigUInt, slippage: BigUInt, swapCreation: BigUInt, swapOwner: String, buyId: String, status: String) {
        self.swapId = swapId
        self.liquidityPoolId = liquidityPoolId
        self.secretHash = secretHash
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
 
    public func encode(to encoder: Encoder) throws {}
}
