import Foundation
import Promises
import BigInt

extension DispatchQueue {
    static let sdk: DispatchQueue = .global(qos: .userInitiated)
}

public final class PortalSwapSDK: BaseClass {
    public enum SwapOperationStatus {
        case none,
             matching,
             canceled,
             swapping,
             failed(String),
             succeded,
             sdkStopped,
             initiated,
             depositing,
             matched,
             holderInvoiced,
             seekerInvoiced,
             holderPaid,
             seekerPaid,
             holderSettled,
             seekerSettled,
             withdrawing
        
        public var description: String {
            switch self {
            case .none:
                return String()
            case .matching:
                return "Matching"
            case .canceled:
                return "Canceled"
            case .swapping:
                return "Swapping"
            case .failed(let reason):
                return "Failed: \(reason)"
            case .succeded:
                return "Succeeded"
            case .sdkStopped:
                return "SDK stopped"
            case .initiated:
                return "Swap initiated"
            case .depositing:
                return "Depositing"
            case .matched:
                return "Swap matched"
            case .holderInvoiced:
                return "Holder invoiced"
            case .seekerInvoiced:
                return "Seeker invoiced"
            case .holderPaid:
                return "Holder paid"
            case .seekerPaid:
                return "Seeker paid"
            case .holderSettled:
                return "Holder settled"
            case .seekerSettled:
                return "Seeker settled"
            case .withdrawing:
                return "Withdraw in-progress"
            }
        }
    }
    
    struct FeeInfo {
        let value: String
        let symbol: String
        let valueInUSD: String
    }
    
    public struct SwapFee {
        let portalFee: FeeInfo
        let sellTxnFee: FeeInfo
        let buyTxnFee: FeeInfo
    }
    
    public struct InvoiceInfo {
        var invoice: String?
        var hash: String?
        var preimage: String?
    }
    
    public enum TransactionStatus: String {
        case pending = "pending"
        case confirmed = "confirmed"
        case failed = "failed"
    }
    
    public final class SwapTransaction {
        public let chainId: String
        
        public var swapId: String?
        public var hash: String?
        
        public let sellAsset: Pool.Asset
        public let buyAsset: Pool.Asset
        public let sellAmount: String
        public var buyAmount: String
        
        public var minedDate = Date.now
        
        public var invoiceInfo: InvoiceInfo?
        
        public var status: TransactionStatus
        public var sellAssetTxnHash: String?
        public var buyAssetTxnHash: String?
        public var swapFee: SwapFee?
        public var fee: String?
        public var error: String?
        
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
    }
    
    private let sdk: Sdk
    
    private var timeoutWorkItem: DispatchWorkItem?
    
    public var swapTransaction: SwapTransaction?
    public var swapStatus: SwapOperationStatus = .none {
        didSet {
            emit(event: "swapStatusUpdated", args: [swapStatus])
        }
    }
    
    public init(config: SwapSdkConfig) {
        DispatchQueue.promises = .sdk
        
        self.sdk = Sdk(config: config)
        
        super.init(id: "SwapSDK")
        
        // Log events
        sdk.on("log") { params in
            print("[\(Date())] LOG: \(params)")
            self.emit(event: "log", args: ["[\(Date())] LOG: \(params)"])
        }
        
        sdk.on("error") { [weak self] args in
            if let self {
                sdk.off("error")
                timeoutWorkItem?.cancel()
                try? awaitPromise(stopSwapSdk())
                emit(event: "error", args: args)
            }
        }
        
        // Basic state events
        let events: [String: SwapState] = [
            "swapHolderInvoiced": .holderInvoiced,
            "swapSeekerInvoiced": .seekerInvoiced,
            "swapHolderSettled": .holderSettled
        ]
        
        events.forEach { event, state in
            sdk.on(event) { [weak self] _ in
                switch state {
                case .matched:
                    self?.swapStatus = .matched
                case .seekerPaid:
                    self?.swapStatus = .seekerPaid
                case .holderPaid:
                    self?.swapStatus = .holderPaid
                case .seekerSettled:
                    self?.swapStatus = .seekerSettled
                case .holderSettled:
                    self?.swapStatus = .holderSettled
                case .holderInvoiced:
                    self?.swapStatus = .holderInvoiced
                case .seekerInvoiced:
                    self?.swapStatus = .seekerInvoiced
                }
            }
        }
    }
    
    public func swap(sellAsset: Pool.Asset, buyAsset: Pool.Asset, sellAmount: String, buyAmount: String) -> Promise<SwapTransaction> {
        Promise { [weak self] resolve, reject in
            guard let self else { return reject(SdkError.instanceUnavailable()) }
            
            swapTransaction = SwapTransaction(
                chainId: sellAsset.blockchainId.description,
                sellAsset: sellAsset,
                buyAsset: buyAsset,
                sellAmount: sellAmount,
                buyAmount: buyAmount,
                status: .pending
            )
            
            swapStatus = .initiated
            
            timeoutWorkItem = DispatchWorkItem {
                reject(SdkError.timedOut(context: [:]))
            }

            DispatchQueue.sdk.asyncAfter(deadline: .now() + 300, execute: timeoutWorkItem!)
            
            do {
                try awaitPromise(sdk.start())
                
                swapStatus = .depositing
                
                let liquidity = try awaitPromise(
                    sdk.deposit(chain: sellAsset.blockchainName, symbol: sellAsset.symbol, amount: BigInt(stringLiteral: sellAmount))
                )
                
                swapTransaction?.sellAssetTxnHash = liquidity.nativeReceipt
                            
                let openOrder = try awaitPromise(
                    sdk.openOrder(
                        sellChain: sellAsset.blockchainName,
                        sellSymbol: sellAsset.symbol,
                        sellAmount: BigInt(stringLiteral: sellAmount),
                        buyChain: buyAsset.blockchainName,
                        buySymbol: buyAsset.symbol,
                        buyAmount: BigInt(stringLiteral: buyAmount),
                        orderType: .market
                    )
                )
                
                print("Open Order: \(openOrder)")
                swapTransaction?.hash = openOrder.id
                
                setupSwapEventListeners(
                    sellAsset: sellAsset,
                    buyAsset: buyAsset,
                    sellAmount: sellAmount,
                    resolve: resolve,
                    reject: reject,
                    timeoutWorkItem: timeoutWorkItem
                )
            } catch {
                timeoutWorkItem?.cancel()
                swapStatus = .failed("\(error)")
                swapTransaction?.status = .failed
                swapTransaction?.error = error.localizedDescription
                reject(error)
            }
        }
    }
    
    private func setupSwapEventListeners(
        sellAsset: Pool.Asset,
        buyAsset: Pool.Asset,
        sellAmount: String,
        resolve: @escaping (SwapTransaction) -> Void,
        reject: @escaping (Error) -> Void,
        timeoutWorkItem: DispatchWorkItem?
    ) {
        
        // Swap Matched Event
        sdk.on("swapMatched") { [weak self] arguments in
            guard let self = self else { return }
            guard let swap = arguments.first as? Swap else { return }
            
            self.swapTransaction?.swapId = swap.id
            self.swapStatus = .matched
            
            // Update buy amount from matched swap
            let buyAmount = swap.secretSeeker.amount
            // Note: You'll need to implement formatUnits equivalent in Swift
            let buyAmountInSwap = self.formatUnits(BigInt(buyAmount), decimals: Int(buyAsset.blockchainDecimals))
            self.swapTransaction?.buyAmount = buyAmountInSwap
        }
        // Swap Holder Paid Event
        .on("swapHolderPaid") { [weak self] arguments in
            guard let self = self else { return }
            guard let swap = arguments.first as? Swap else { return }

            self.swapStatus = .holderPaid
            
            if swap.secretHolder.symbol == sellAsset.symbol {
                self.swapTransaction?.sellAssetTxnHash = swap.secretHolder.receipt
            } else {
                self.swapTransaction?.buyAssetTxnHash = swap.secretHolder.receipt
            }
        }
        // Swap Seeker Paid Event
        .on("swapSeekerPaid") { [weak self] arguments in
            guard let self = self else { return }
            guard let swap = arguments.first as? Swap else { return }
            
            self.swapStatus = .seekerPaid
            
            // Update transaction hashes
            if swap.secretHolder.symbol == sellAsset.symbol {
                self.swapTransaction?.sellAssetTxnHash = swap.secretHolder.receipt
            } else {
                self.swapTransaction?.buyAssetTxnHash = swap.secretHolder.receipt
            }
            
            self.swapTransaction?.buyAssetTxnHash = swap.secretSeeker.receipt
        }
        // Swap Seeker Settled Event - Final step
        .on("swapSeekerSettled") { [weak self] _ in
            guard let self = self else { return }
            
            do {
                self.swapStatus = .holderSettled
                self.swapStatus = .withdrawing
                
                let liquidity = try awaitPromise(
                    self.sdk.withdraw(
                        chain: sellAsset.blockchainName,
                        symbol: sellAsset.symbol,
                        amount: BigInt(stringLiteral: sellAmount)
                    )
                )
                
                // Success - update transaction
                self.swapStatus = .succeded
                self.swapTransaction?.status = .confirmed
                self.swapTransaction?.error = nil
                
                try awaitPromise(self.stopSwapSdk())
                
                timeoutWorkItem?.cancel()
                
                if let transaction = self.swapTransaction {
                    resolve(transaction)
                } else {
                    reject(NSError(domain: "PortalSwapSDK", code: -3, userInfo: [NSLocalizedDescriptionKey: "Transaction is nil"]))
                }
            } catch {
                swapTransaction?.status = .failed
                swapTransaction?.error = error.localizedDescription
                swapStatus = .failed("\(error)")
                timeoutWorkItem?.cancel()
                reject(error)
                
                try? awaitPromise(self.stopSwapSdk())
            }
        }
    }
    
    private func stopSwapSdk() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            try awaitPromise(sdk.stop())
            swapStatus = .sdkStopped
        }
    }
    
    // Helper function to format units (equivalent to ethers.utils.formatUnits)
    private func formatUnits(_ value: BigInt, decimals: Int) -> String {
        let divisor = pow(10.0, Double(decimals))
        let doubleValue = Double(value.description) ?? 0
        return String(doubleValue / divisor)
    }
}
