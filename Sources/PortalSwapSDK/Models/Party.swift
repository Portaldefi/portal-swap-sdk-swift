final class Party: Codable {
    let id: String
    let quantity: Int64
    
    var swap: AmmSwap?
    var invoice: [String: String]?
    var receip: [String: String]?
    
    private enum CodingKeys: String, CodingKey {
        case id, invoice, quantity
    }

    func update(swap: AmmSwap) {
        self.swap = swap
    }
        
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        quantity = try container.decode(Int64.self, forKey: .quantity)
        invoice = try? container.decode([String:String].self, forKey: .invoice)
        swap = nil
    }
    
    init(id: String, quantity: Int64, swap: AmmSwap) {
        self.id = id
        self.quantity = quantity
        self.swap = swap
    }
}

extension Party: Equatable {
    public static func == (lhs: Party, rhs: Party) -> Bool {
        lhs.id == rhs.id
    }
}
