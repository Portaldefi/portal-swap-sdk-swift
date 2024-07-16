import Foundation

public struct OrderRequest {
    public let secret: Data
    public let buyAsset: String
    public let buyNetwork: String
    public let buyQuantity: Int
    public let sellAsset: String
    public let sellNetwork: String
    public let sellQuantity: Int
    
    public init(secret: Data, buyAsset: String, buyNetwork: String, buyQuantity: Int, sellAsset: String, sellNetwork: String, sellQuantity: Int) {
        self.secret = secret
        self.buyAsset = buyAsset
        self.buyNetwork = buyNetwork
        self.buyQuantity = buyQuantity
        self.sellAsset = sellAsset
        self.sellNetwork = sellNetwork
        self.sellQuantity = sellQuantity
    }
}
