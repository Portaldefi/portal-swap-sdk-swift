import Foundation

struct InvoiceSettledEvent: Codable {
    let id: String
    let swap: String
    let payer: String
    let payee: String
    let asset: String
    let eventSignature: String
    let address: String
    let quantity: String
    let removed: Bool
    let secret: String
    
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

        // Decode non-indexed fields: payer, payee, asset, quantity, secret
        let dataSubstring = data.dropFirst(2) // Remove "0x" prefix
        let payerHex = String(dataSubstring.prefix(64))
        payer = payerHex

        let remainingData1 = dataSubstring.dropFirst(64)
        let payeeHex = String(remainingData1.prefix(64))
        payee = payeeHex

        let remainingData2 = remainingData1.dropFirst(64)
        let assetHex = String(remainingData2.prefix(64))
        asset = assetHex

        let remainingData3 = remainingData2.dropFirst(64)
        let quantityHex = String(remainingData3.prefix(64))
        quantity = quantityHex

        let secretHex = String(remainingData3.dropFirst(64))
        secret = secretHex
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([eventSignature, id, swap], forKey: .topics)
        let dataValue = payer + payee + asset + quantity + secret
        try container.encode(dataValue, forKey: .data)
    }
}
