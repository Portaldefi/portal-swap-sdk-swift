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

struct AuthorizedEvent: Codable {
    // Event properties
    let address: String
    let topics: [String]
    let data: String
    let blockNumber: String
    let transactionHash: String
    let transactionIndex: String
    let blockHash: String
    let logIndex: String
    let removed: Bool
    
    // Decoded parameter
    let swapId: String
    
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all required fields
        address = try container.decode(String.self, forKey: .address)
        topics = try container.decode([String].self, forKey: .topics)
        data = try container.decode(String.self, forKey: .data)
        blockNumber = try container.decode(String.self, forKey: .blockNumber)
        transactionHash = try container.decode(String.self, forKey: .transactionHash)
        transactionIndex = try container.decode(String.self, forKey: .transactionIndex)
        blockHash = try container.decode(String.self, forKey: .blockHash)
        logIndex = try container.decode(String.self, forKey: .logIndex)
        removed = try container.decode(Bool.self, forKey: .removed)
        
        // Decode swapId from data
        guard let decodedSwapId = AuthorizedEvent.decodeSwapId(from: data) else {
            throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Unable to decode swapId from data")
        }
        swapId = decodedSwapId
    }
    
    public func encode(to encoder: Encoder) throws {
        // Implement encoding if necessary
    }
    
    // Function to decode swapId from data
    static func decodeSwapId(from data: String) -> String? {
        // Remove '0x' prefix if present
        let dataHexString = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        
        // Ensure data is 64 hex characters (32 bytes)
        guard dataHexString.count == 64 else {
            print("Data length is not 64 hex characters")
            return nil
        }
        
        // Return the swapId with '0x' prefix
        return "0x" + dataHexString
    }
}
