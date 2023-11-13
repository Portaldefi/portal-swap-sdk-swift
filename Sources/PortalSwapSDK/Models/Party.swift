public struct Party: Codable {
    struct SwapId: Codable {
        let id: String
    }

    struct Asset: Codable {
        let name: String
        let symbol: String
        let contractAddress: String?
    }

    struct AssetNetwork: Codable {
        let name: String
        let type: String
        
        private enum CodingKeys: String, CodingKey {
            case name
            case type = "@type"
        }
    }

    struct InvoiceCodable: Codable {
        let created_at: String
        let id: String
        let mtokens: String
        let request: String
        let tokens: Int64
        
        private enum CodingKeys: String, CodingKey {
            case created_at, id, mtokens, request, tokens
        }
    }
    
    let swap: Swap?
    let id: String
    let asset: String
    let blockchain: String
    let quantity: Int64
    let oid: String
    let invoice: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, asset, blockchain, invoice, oid, quantity
    }
    
    public var isSecretSeeker: Bool {
        false
    }
    
    public var isSecretHolder: Bool {
        false
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        asset = try container.decode(String.self, forKey: .asset)
        blockchain = try container.decode(String.self, forKey: .blockchain)
        quantity = try container.decode(Int64.self, forKey: .quantity)
        oid = try container.decode(String.self, forKey: .oid)
        invoice = try? container.decode(String.self, forKey: .oid)
        swap = nil
    }
}
