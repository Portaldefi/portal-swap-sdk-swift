import Foundation
import BigInt

public class Order {
    public enum OrderType: Int8 {
        case market = 0, limit
    }

    public var id: String
    public let ts: Int
    public let trader: String
    public let sellAsset: String
    public let sellAmount: BigInt
    public let buyAsset: String
    public let buyAmount: BigInt
    public let orderType: OrderType
    public let metadata: String?

    public init(id: String? = nil, ts: Int? = nil, trader: String, sellAsset: String, sellAmount: BigInt, buyAsset: String, buyAmount: BigInt, orderType: OrderType, metadata: String? = nil) throws {
        if sellAsset == buyAsset {
            throw SdkError(message: "Sell and buy assets cannot be the same", code: "Order")
        }
        
        if sellAmount < 0 {
            throw SdkError(message: "Sell amount must be a positive number", code: "Order")
        }
        
        if buyAmount < 0 {
            throw SdkError(message: "Buy amount must be a positive number", code: "Order")
        }
        
        self.id = id ?? String(repeating: "0", count: 66) // "0x" + 64 zeros
        self.ts = ts ?? 0
        self.trader = trader
        self.sellAsset = sellAsset
        self.sellAmount = sellAmount
        self.buyAsset = buyAsset
        self.buyAmount = buyAmount
        self.orderType = orderType
        self.metadata = metadata
    }
    
    public func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "ts": ts,
            "trader": trader,
            "sellAsset": sellAsset,
            "sellAmount": sellAmount.description,
            "buyAsset": buyAsset,
            "buyAmount": buyAmount.description,
            "orderType": orderType.rawValue
        ]
        if let metadata = metadata {
            json["metadata"] = metadata
        }
        return json
    }    
}
