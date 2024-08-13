public struct AmmSwapModel {
    public let swapId: String
    public let status: String
    public let secretHash: String
    
    public let sellerAddress: String
    public let sellNetwork: String
    public let sellAsset: String
    public let sellAmount: String
    
    public let buyAddress: String
    public let buyNetwork: String
    public let buyAsset: String
    public let buyAmount: String

    public let buyAmountSlippage: String
    public let tsCreation: String
    
    init(record: DBAmmSwap) throws {
        self.swapId = record.swapId!
        self.status = record.status!
        self.secretHash = record.secretHash!
        self.sellerAddress = record.sellerAddress!
        self.sellNetwork = record.sellNetwork!
        self.sellAsset = record.sellAsset!
        self.sellAmount = record.sellAmount!
        self.buyAddress = record.buyAddress!
        self.buyNetwork = record.buyNetwork!
        self.buyAsset = record.buyAsset!
        self.buyAmount = (record.buyQuantity != nil) ?  record.buyQuantity! : record.buyAmount!
        self.buyAmountSlippage = record.buyAmountSlippage!
        self.tsCreation = record.tsCreation!
    }
}
