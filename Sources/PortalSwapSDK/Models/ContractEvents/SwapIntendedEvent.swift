//
//  SwapIntendedEvent.swift
//
//
//  Created by farid on 03.06.2024.
//

import Foundation
import BigInt

struct SwapIntendedEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }
    
    let swapOwner: String
    let secretHash: String
    let traderBuyId: BigUInt
    let sellAsset: String
    let sellAmount: BigUInt
    let buyAsset: String
    let buyAmount: BigUInt
    let buyAmountSlippage: BigUInt
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
        let swapOwnerHex = String(dataSubstring.prefix(64))
        swapOwner = decodeAddress(from: swapOwnerHex)
        
        let remainingData1 = dataSubstring.dropFirst(64)
        let secretHashHex = String(remainingData1.prefix(64))
        secretHash = secretHashHex
        
        let remainingData2 = remainingData1.dropFirst(64)
        let traderBuyIdHex = String(remainingData2.prefix(64))
        traderBuyId = decodeBigUInt(from: traderBuyIdHex)
        
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
        let buyAmountSlippageHex = String(remainingData7.prefix(64))
        buyAmountSlippage = decodeBigUInt(from: buyAmountSlippageHex)
        
        let remainingData8 = remainingData7.dropFirst(64)
        let swapIdHex = String(remainingData8.prefix(64))
        swapId = swapIdHex
        
        let remainingData9 = remainingData8.dropFirst(64)
        let swapCreationHex = String(remainingData9.prefix(64))
        swapCreation = decodeBigUInt(from: swapCreationHex)
    }
    
    public func encode(to encoder: Encoder) throws {}
}
