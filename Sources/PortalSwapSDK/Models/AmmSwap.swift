//
//  AmmSwap.swift
//
//
//  Created by farid on 14.06.2024.
//

import Foundation
import BigInt
import Promises

final class AmmSwap: BaseClass, Codable {
    private enum CodingKeys: String, CodingKey {
        case swapId, status, secretHash, sellerAddress, sellNetwork, sellAsset, sellAmount, buyNetwork, buyAddress, buyAsset, buyAmount, buyQuantity, buyAmountSlippage, tsCreation
    }
    
    let AMM_SWAP_STATUS = [
        "trader.intent.created",
        "trader.intent.sent.to.notary",
        "notary.trader.intent.created",
        "notary.intent.timer.started",
        "notary.trader.intent.sent",
        "notary.lp.notified.intent",
        "notary.lp.commit.liquidity",
        "notary.intent.timer.ended",
        "notary.validator.match.intent",
        "notary.match.intent.sent.to.matchedlp",
        "lp.invoice.created",
        "lp.invoice.sent",
        "intent.authorized",
        "lp.invoice.paid",
        "trader.settle.invoice",
        "lp.settle.invoice"
    ]
    
    let swapId: String
    let secretHash: String
    let sellerAddress: String
    let sellNetwork: String
    let sellAsset: String
    let sellAmount: BigUInt
    let buyAddress: String
    let buyNetwork: String
    let buyAsset: String
    let buyAmount: BigUInt
    let buyAmountSlippage: BigUInt
    let tsCreation: String
    
    var status: String
    var buyQuantity: Int64?

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        swapId = try container.decode(String.self, forKey: .swapId)
        status = try container.decode(String.self, forKey: .status)
        secretHash = try container.decode(String.self, forKey: .secretHash)
        sellerAddress = try container.decode(String.self, forKey: .sellerAddress)
        sellNetwork = try container.decode(String.self, forKey: .sellNetwork)
        sellAsset = try container.decode(String.self, forKey: .sellAsset)
        sellAmount = try container.decode(BigUInt.self, forKey: .sellAmount)
        buyAddress = try container.decode(String.self, forKey: .buyAddress)
        buyNetwork = try container.decode(String.self, forKey: .buyNetwork)
        buyAsset = try container.decode(String.self, forKey: .buyAsset)
        buyAmount = try container.decode(BigUInt.self, forKey: .buyAmount)
        buyAmountSlippage = try container.decode(BigUInt.self, forKey: .buyAmountSlippage)
        tsCreation = try container.decode(String.self, forKey: .tsCreation)

        if let buyQuantity = try? container.decode(Int64.self, forKey: .buyQuantity) {
            self.buyQuantity = buyQuantity
        }
        
        super.init(id: "AmmSwap: \(swapId)")
    }
    
    init(event: SwapIntendedEvent) {
        swapId = "0x\(event.swapId)"
        status = "trader.intent.created"
        secretHash = event.secretHash
        sellerAddress = event.swapOwner
        sellNetwork = "ethereum"
        sellAsset = event.sellAsset
        sellAmount = event.sellAmount
        buyAddress = event.traderBuyId.description
        buyNetwork = "lightning"
        buyAsset = event.buyAsset
        buyAmount = event.buyAmount
        buyAmountSlippage = event.buyAmountSlippage
        tsCreation = event.swapCreation.description
        
        super.init(id: "amm.swap")
    }
    
    init(record: DBAmmSwap) {
        swapId = record.swapId!
        status = record.status!
        secretHash = record.secretHash!
        sellerAddress = record.sellerAddress!
        sellNetwork = record.sellNetwork!
        sellAsset = record.sellAsset!
        sellAmount = BigUInt(stringLiteral: record.sellAmount!)
        buyAddress = record.buyAddress!
        buyNetwork = record.buyNetwork!
        buyAsset = record.buyAsset!
        buyAmount = BigUInt(stringLiteral: record.buyAmount!)
        buyAmountSlippage = BigUInt(stringLiteral: record.buyAmountSlippage!)
        tsCreation = record.tsCreation!
        
        if let quantity = record.buyQuantity, let buyQuantity = Int64(quantity) {
            self.buyQuantity = buyQuantity
        }
        
        super.init(id: "amm.swap.\(swapId)")
    }
        
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(swapId, forKey: .swapId)
        try container.encode(status, forKey: .status)
        try container.encode(secretHash, forKey: .secretHash)
        
        try container.encode(sellNetwork, forKey: .sellNetwork)
        try container.encode(sellAsset, forKey: .sellAsset)
        try container.encode(sellerAddress, forKey: .sellerAddress)
        try container.encode(sellAmount, forKey: .sellAmount)
        
        try container.encode(buyNetwork, forKey: .buyNetwork)
        try container.encode(buyAddress, forKey: .buyAddress)
        try container.encode(buyAsset, forKey: .buyAsset)
        try container.encode(buyAmount, forKey: .buyAmount)
        try container.encode(buyQuantity, forKey: .buyQuantity)
        
        try container.encode(buyAmountSlippage, forKey: .buyAmountSlippage)
        try container.encode(tsCreation, forKey: .tsCreation)
    }
    
    func update(swap: AmmSwap) throws {
        guard swapId == swap.swapId else {
            throw SwapSDKError.msg("amm swap id mismatch")
        }
        
        
    }
}

extension AmmSwap {
    func toJSON() -> [String: Any] {
        Utils.convertToJSON(self) ?? [:]
    }
    
    static func from(json: [String: Any]) throws -> AmmSwap {
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        return try JSONDecoder().decode(AmmSwap.self, from: jsonData)
    }
    
    static func from(swapIntendedEvent: SwapIntendedEvent) -> AmmSwap {
        AmmSwap(event: swapIntendedEvent)
    }
}
