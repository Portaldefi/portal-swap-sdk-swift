import Foundation
import BigInt

public final class SwapTransaction: Codable {
    struct FeeInfo: Codable {
        let value: String
        let symbol: String
        let valueInUSD: String
    }

    public struct SwapFee: Codable {
        let portalFee: FeeInfo
        let sellTxnFee: FeeInfo
        let buyTxnFee: FeeInfo
    }

    public struct InvoiceInfo: Codable {
        var invoice: String?
        var hash: String?
        var preimage: String?
    }

    public enum TransactionStatus: String, Codable {
        case pending = "pending"
        case confirmed = "confirmed"
        case failed = "failed"
    }
    
    public let chainId: String
    
    public var swapId: String?
    public var hash: String?
    
    public let sellAsset: Pool.Asset
    public let buyAsset: Pool.Asset
    public var sellAmount: String
    public var buyAmount: String
    
    public var minedDate = Date.now
    
    public var invoiceInfo = InvoiceInfo()
    
    public var status: TransactionStatus
    public var sellAssetTxnHash: String?
    public var buyAssetTxnHash: String?
    public var swapFee: SwapFee?
    public var fee: String?
    public var error: String?
    
    public var uiSellAmount: String {
        let decimals = BigUInt(10).power(Int(sellAsset.blockchainDecimals))
        return "\(Decimal(string: sellAmount)! / Decimal(string: decimals.description)!)"
    }
    
    public var uiBuyAmount: String {
        let decimals = BigUInt(10).power(Int(buyAsset.blockchainDecimals))
        return "\(Decimal(string: buyAmount)! / Decimal(string: decimals.description)!)"
    }
        
    init(chainId: String, swapId: String? = nil, sellAsset: Pool.Asset, buyAsset: Pool.Asset, sellAmount: String, buyAmount: String, status: TransactionStatus, sellAssetTxnHash: String? = nil, buyAssetTxnHash: String? = nil, swapFee: SwapFee? = nil, fee: String? = nil, error: String? = nil) {
        self.chainId = chainId
        self.swapId = swapId
        self.sellAsset = sellAsset
        self.buyAsset = buyAsset
        self.sellAmount = sellAmount
        self.buyAmount = buyAmount
        self.status = status
        self.sellAssetTxnHash = sellAssetTxnHash
        self.buyAssetTxnHash = buyAssetTxnHash
        self.swapFee = swapFee
        self.fee = fee
        self.error = error
    }
    
    static func from(record: DBSwapTransaction) throws -> SwapTransaction {
        guard
            let jsonString = record.jsonData,
            let jsonData = jsonString.data(using: .utf8)
        else {
            throw SwapSDKError.msg("Invalid JSON data for SwapTransaction")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        
        return try decoder.decode(SwapTransaction.self, from: jsonData)
    }
}
