//
//  SwapIntent.swift
//  
//
//  Created by farid on 14.06.2024.
//

import Foundation

public struct SwapIntent {
    public let secretHash: Data
    public let traderBuyId: UInt64
    public let buyAmount: UInt64
    public let buyAddress: String
    public let sellAmount: UInt64
    public let sellAddress: String
    public let buyAmountSlippage: UInt64
    
    public init(secretHash: Data, traderBuyId: UInt64, buyAmount: UInt64, buyAddress: String, sellAmount: UInt64, sellAddress: String, buyAmountSlippage: UInt64) {
        self.secretHash = secretHash
        self.traderBuyId = traderBuyId
        self.buyAmount = buyAmount
        self.buyAddress = buyAddress
        self.sellAmount = sellAmount
        self.sellAddress = sellAddress
        self.buyAmountSlippage = buyAmountSlippage
    }
}

