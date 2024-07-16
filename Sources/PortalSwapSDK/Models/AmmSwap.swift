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
        case swapId, status, secretHash, sellerAddress, sellNetwork, sellAsset, sellAmount, buyNetwork, buyAddress, buyAsset, buyAmount, buyAmountSlippage, tsCreation
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
    let status: String
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

        super.init(id: "AmmSwap")
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
        
    func encode(to encoder: Encoder) throws {}
    
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
