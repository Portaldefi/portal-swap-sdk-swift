public struct Order: Decodable {
    public let id: String
    public let ts: Int64
    public let uid: String
    public let type: OrderType
    public let side: OrderSide
    public let baseAsset: String
    public let baseQuantity: Int32
    public let baseNetwork: String
    public let quoteAsset: String
    public let quoteQuantity: Int64
    public let quoteNetwork: String
    public let status: OrderStatus
    public let reason: String?
    
    public enum OrderType: String, Decodable {
        case limit, market
    }

    public enum OrderSide: String, Decodable {
        case ask, bid
    }
    
    public enum OrderStatus: String, Decodable {
        case created, opened, commiting, commited
    }

    enum CodingKeys: String, CodingKey {
        case id, 
             ts,
             uid,
             type,
             side,
             hash,
             baseAsset,
             baseQuantity,
             baseNetwork,
             quoteAsset,
             quoteQuantity,
             quoteNetwork,
             status,
             reason
    }
    
    public init(
        id: String,
        ts: Int64,
        uid: String,
        type: OrderType,
        side: OrderSide,
        baseAsset: String,
        baseQuantity: Int32,
        baseNetwork: String,
        quoteAsset: String,
        quoteQuantity: Int64,
        quoteNetwork: String,
        status: OrderStatus,
        reason: String?
    ) {
        self.id = id
        self.ts = ts
        self.uid = uid
        self.type = type
        self.side = side
        self.baseAsset = baseAsset
        self.baseQuantity = baseQuantity
        self.baseNetwork = baseNetwork
        self.quoteAsset = quoteAsset
        self.quoteQuantity = quoteQuantity
        self.quoteNetwork = quoteNetwork
        self.status = status
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ts = try container.decode(Int64.self, forKey: .ts)
        uid = try container.decode(String.self, forKey: .uid)
        baseAsset = try container.decode(String.self, forKey: .baseAsset)
        baseQuantity = try container.decode(Int32.self, forKey: .baseQuantity)
        baseNetwork = try container.decode(String.self, forKey: .baseNetwork)
        quoteAsset = try container.decode(String.self, forKey: .quoteAsset)
        quoteQuantity = try container.decode(Int64.self, forKey: .quoteQuantity)
        quoteNetwork = try container.decode(String.self, forKey: .quoteNetwork)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        
        let statusString = try container.decode(String.self, forKey: .status)
        guard let typeValue = OrderStatus(rawValue: statusString) else {
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Invalid order status")
        }
        status = typeValue

        let typeString = try container.decode(String.self, forKey: .type)
        guard let typeValue = OrderType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid order type")
        }
        type = typeValue

        let sideString = try container.decode(String.self, forKey: .side)
        guard let sideValue = OrderSide(rawValue: sideString) else {
            throw DecodingError.dataCorruptedError(forKey: .side, in: container, debugDescription: "Invalid swap side")
        }
        side = sideValue
    }
}
