final class Party: Codable {
    let id: String
    let oid: String

    let asset: String
    let blockchain: String
    let quantity: Int64
    
    var partyType: PartyType {
        guard let swap = swap else {
            fatalError("Party id: \(id), error: swap is nil")
        }
        return swap.partyType
    }
    
    var swap: Swap?
    var invoice: [String: String]?
    var receip: [String: String]?
    
    private enum CodingKeys: String, CodingKey {
        case id, asset, blockchain, invoice, oid, quantity
    }

    func update(swap: Swap) {
        self.swap = swap
    }
        
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        asset = try container.decode(String.self, forKey: .asset)
        blockchain = try container.decode(String.self, forKey: .blockchain)
        quantity = try container.decode(Int64.self, forKey: .quantity)
        oid = try container.decode(String.self, forKey: .oid)
        invoice = try? container.decode([String:String].self, forKey: .invoice)
        swap = nil
    }
}

extension Party: Equatable {
    public static func == (lhs: Party, rhs: Party) -> Bool {
        lhs.id == rhs.id
    }
}
