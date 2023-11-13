import Foundation
import Promises

struct APIRequest {
    let method: String
    let path: String
}

struct OrderData: Codable {
    let id: UUID
    let uid: String
    let side: String
    let baseAsset: String
    let baseNetwork: String
    let baseQuantity: Int32
    let quoteAsset: String
    let quoteNetwork: String
    let quoteQuantity: Int64
}

public class Dex: BaseClass {
    private var sdk: Sdk
    
    init(sdk: Sdk, props: [String: Any]) {
        self.sdk = sdk
        super.init()
    }
    
    // Opens the orderbooks
    func open() -> Promise<Dex> {
        Promise { fulfill, reject in
            fulfill(self)
        }
    }
    
    // Closes the orderbooks
    func close() -> Promise<Dex> {
        Promise { fulfill, reject in
            fulfill(self)
        }
    }
    
    // Adds a limit order to the orderbook
    func submitLimitOrder(_ request: OrderRequest) -> Promise<Order> {
        let args = [
            "method": "PUT",
            "path": "/api/v1/orderbook/limit"
        ]
        
        let data = [
            "id": UUID().uuidString,
            "uid": sdk.id!,
            "side": request.side,
            "baseAsset": request.baseAsset,
            "baseNetwork": request.baseNetwork,
            "baseQuantity": request.baseQuantity,
            "quoteAsset": request.quoteAsset,
            "quoteNetwork": request.quoteNetwork,
            "quoteQuantity": request.quoteQuantity
        ] as [String : Any]
                        
        return sdk.network.request(args: args, data: data).then { try JSONDecoder().decode(Order.self, from: $0) }
    }
    
    // Cancel limit order
    func cancelLimitOrder(_ order: Order) -> Promise<Order> {
        let args = [
            "method": "DELETE",
            "path": "/api/v1/orderbook/limit"
        ]
        
        let data = [
            "id": order.id,
            "baseAsset": order.baseAsset,
            "quoteAsset": order.quoteAsset
        ] as [String : Any]
                
        return sdk.network.request(args: args, data: data).then { try JSONDecoder().decode(Order.self, from: $0) }
    }
}
