import Foundation
import BigInt

struct OrderCreatedEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }
    
    let secretHash: String
    let sellAsset: String
    let sellAmount: BigUInt
    let swapOwner: String
    let swapId: String
    let swapCreation: BigUInt
    
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
        
        // Extract and decode each parameter
        let secretHashHex = String(dataSubstring.prefix(64))
        secretHash = secretHashHex
        
        let remainingData1 = dataSubstring.dropFirst(64)
        let sellAssetHex = String(remainingData1.prefix(64))
        sellAsset = decodeAddress(from: sellAssetHex)
        
        let remainingData2 = remainingData1.dropFirst(64)
        let sellAmountHex = String(remainingData2.prefix(64))
        sellAmount = decodeBigUInt(from: sellAmountHex)
        
        let remainingData3 = remainingData2.dropFirst(64)
        let swapOwnerHex = String(remainingData3.prefix(64))
        swapOwner = decodeAddress(from: swapOwnerHex)
        
        let remainingData4 = remainingData3.dropFirst(64)
        let swapIdHex = String(remainingData4.prefix(64))
        swapId = swapIdHex
        
        let remainingData5 = remainingData4.dropFirst(64)
        let swapCreationHex = String(remainingData5.prefix(64))
        swapCreation = decodeBigUInt(from: swapCreationHex)
    }
    
    public func encode(to encoder: Encoder) throws {}
}

