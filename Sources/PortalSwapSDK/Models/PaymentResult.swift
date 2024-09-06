public struct PaymentResult {
    public struct Swap {
        public let id: String
        
        public init(id: String) {
            self.id = id
        }
    }
    public let id: String
    public let swap: Swap
    public let request: String
    public let amount: Int64
    public let memo: String
    
    public init(id: String, swap: Swap, request: String, amount: Int64, memo: String) {
        self.id = id
        self.swap = swap
        self.request = request
        self.amount = amount
        self.memo = memo
    }
}
