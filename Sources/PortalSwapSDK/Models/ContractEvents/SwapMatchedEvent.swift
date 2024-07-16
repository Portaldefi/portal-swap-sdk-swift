//
//  SwapMatchedEvent.swift
//
//
//  Created by farid on 14.06.2024.
//

import BigInt

struct SwapMatchedEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }

    let swapId: String
    let liquidityOwner: String
    let liquidityId: BigUInt
    let matchedSellAmount: BigUInt
    let matchedBuyAmount: BigUInt

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topics = try container.decode([String].self, forKey: .topics)
        let dataString = try container.decode(String.self, forKey: .data)
        
        // Decode indexed parameters
        guard topics.count >= 3 else {
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
            return BigUInt(hexString, radix: 16) ?? BigUInt(0)
        }
        
        swapId = topics[1]
        liquidityOwner = decodeAddress(from: topics[2])
        
        var dataSubstring = dataString.dropFirst(2) // Remove "0x" prefix
        
        let liquidityIdHex = String(dataSubstring.prefix(64))
        liquidityId = decodeBigUInt(from: liquidityIdHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let matchedSellAmountHex = String(dataSubstring.prefix(64))
        matchedSellAmount = decodeBigUInt(from: matchedSellAmountHex)
        dataSubstring = dataSubstring.dropFirst(64)
        
        let matchedBuyAmountHex = String(dataSubstring.prefix(64))
        matchedBuyAmount = decodeBigUInt(from: matchedBuyAmountHex)
    }

    public func encode(to encoder: Encoder) throws {}
}
