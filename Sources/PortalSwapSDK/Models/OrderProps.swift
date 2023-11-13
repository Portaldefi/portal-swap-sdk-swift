public struct OrderRequest {
    public let baseAsset: String
    public let baseNetwork: String
    public let baseQuantity: Int
    public let quoteAsset: String
    public let quoteNetwork: String
    public let quoteQuantity: Int
    public let side: String
    
    public init(baseAsset: String, baseNetwork: String, baseQuantity: Int, quoteAsset: String, quoteNetwork: String, quoteQuantity: Int, side: String) {
        self.baseAsset = baseAsset
        self.baseNetwork = baseNetwork
        self.baseQuantity = baseQuantity
        self.quoteAsset = quoteAsset
        self.quoteNetwork = quoteNetwork
        self.quoteQuantity = quoteQuantity
        self.side = side
    }
}
