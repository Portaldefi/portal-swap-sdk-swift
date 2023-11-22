import Foundation

struct InvoiceCreatedEvent: Codable {
    let id: String
    let swap: String
    let payee: String
    let asset: String
    let quantity: String
    let eventSignature: String
    let address: String
    let removed: Bool
    
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, removed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topics = try container.decode([String].self, forKey: .topics)
        let data = try container.decode(String.self, forKey: .data)
        
        address = try container.decode(String.self, forKey: .address)
        removed = try container.decode(Bool.self, forKey: .removed)

        guard topics.count >= 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .topics,
                in: container,
                debugDescription: "Expected at least 3 topics."
            )
        }
        
        eventSignature = topics[0]
        id = topics[1]
        swap = topics[2]

        // The data field contains the concatenated non-indexed parameters (payee, asset, and quantity).
        // Each parameter is 32 bytes long, represented as 64 hex characters.
        let dataSubstring = data.dropFirst(2) // Remove "0x" prefix
        let payeeHex = String(dataSubstring.prefix(64))
        payee = payeeHex

        let remainingData = dataSubstring.dropFirst(64)
        let assetHex = String(remainingData.prefix(64))
        asset = assetHex

        let quantityHex = String(remainingData.dropFirst(64))
        quantity = quantityHex
    }
    
    func encode(to encoder: Encoder) throws {
        // Dummy implementation: not actually encoding back to the original format
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([eventSignature, id, swap], forKey: .topics)
        let dataValue = payee + asset + quantity
        try container.encode(dataValue, forKey: .data)
    }
}
