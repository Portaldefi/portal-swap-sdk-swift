//
//  InvoiceRegisteredEvent.swift
//  
//
//  Created by farid on 14.06.2024.
//

import Foundation

struct InvoiceRegisteredEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }

    let swapId: String
    let invoice: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topics = try container.decode([String].self, forKey: .topics)
        
        // Decode the indexed parameter (swapId)
        guard topics.count > 1 else {
            throw SwapSDKError.msg("Invalid number of topics")
        }
        swapId = topics[1]
        
        // Decode the non-indexed parameters from the data field
        invoice = try container.decode(String.self, forKey: .data)
    }
    
    public func encode(to encoder: Encoder) throws {}
}
