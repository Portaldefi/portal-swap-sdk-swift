import Foundation
import BigInt

struct InvoiceCreatedEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }

    let swapId: String
    let swapOwner: String
    let counterParty: String
    let sellAsset: String
    let sellAmount: BigUInt

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topics = try container.decode([String].self, forKey: .topics)
        let dataString = try container.decode(String.self, forKey: .data)

        // Decode indexed parameters
        guard topics.count >= 4 else {
            throw SwapSDKError.msg("Insufficient topics to decode indexed parameters")
        }
        
        func decodeAddress(from hexString: String) -> String {
            var hex = hexString
            if hex.hasPrefix("0x") {
                hex.removeFirst(2)
            }
            return "0x" + hex.suffix(40)
        }

        func decodeBigUInt(from hexString: String) -> BigUInt {
            BigUInt(hexString, radix: 16) ?? BigUInt(0)
        }

        swapId = topics[1]
        swapOwner = decodeAddress(from: topics[2])
        counterParty = decodeAddress(from: topics[3])

        // Decode non-indexed parameters
        var dataSubstring = dataString.dropFirst(2) // Remove "0x" prefix

        let sellAssetHex = String(dataSubstring.prefix(64))
        sellAsset = decodeAddress(from: sellAssetHex)
        dataSubstring = dataSubstring.dropFirst(64)

        let sellAmountHex = String(dataSubstring.prefix(64))
        sellAmount = decodeBigUInt(from: sellAmountHex)
    }
    
    public init(swapId: String, swapOwner: String, counterParty: String, sellAsset: String, sellAmount: BigUInt) {
        self.swapId = swapId
        self.swapOwner = swapOwner
        self.counterParty = counterParty
        self.sellAsset = sellAsset
        self.sellAmount = sellAmount
    }

    public func encode(to encoder: Encoder) throws {}
}
