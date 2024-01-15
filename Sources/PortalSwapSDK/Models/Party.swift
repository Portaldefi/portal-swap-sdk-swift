public class Party: Codable {
    let id: String
    let oid: String

    public let asset: String
    public let blockchain: String
    public let quantity: Int64
    
    public var swap: Swap?
    public var invoice: [String: String]?
    public var receip: [String: String]?
    
    private enum CodingKeys: String, CodingKey {
        case id, asset, blockchain, invoice, oid, quantity
    }
    
    var isSecretSeeker: Bool {
        guard let swap = swap else {
            fatalError("Party id: \(id), error: swap is nil")
        }
        return swap.partyType == "seeker"
    }
    
    var isSecretHolder: Bool {
        guard let swap = swap else {
            fatalError("Party id: \(id), error: swap is nil")
        }
        return swap.partyType == "holder"
    }
    
    func update(swap: Swap) {
        self.swap = swap
    }
        
    required public init(from decoder: Decoder) throws {
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
