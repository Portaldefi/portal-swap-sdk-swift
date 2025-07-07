import Foundation
import Promises
import BigInt

public final class PortalSwapSDK: BaseClass {
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
                self.swapTransaction?.status = .failed
                self.swapTransaction?.error = "Swap operation timed out"
                
                self.updateSwapTx()
                
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
            let buyAmountInSwap = self.formatUnits(BigInt(buyAmount), decimals: Int(buyAsset.blockchainDecimals))
            self.swapTransaction?.buyAmount = buyAmountInSwap
            
            updateSwapTx()
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
            
            updateSwapTx()
        }
        // Swap Seeker Paid Event
        .on("swapSeekerPaid") { [weak self] arguments in
            guard let self = self else { return }
            guard let swap = arguments.first as? Swap else { return }
            
            swapStatus = .seekerPaid
            
            swapTransaction?.invoiceInfo.invoice = swap.secretSeeker.invoice
            swapTransaction?.invoiceInfo.hash = swap.secretSeeker.receipt
            
            swapTransaction?.buyAssetTxnHash = swap.secretSeeker.receipt
            
            if swap.secretSeeker.symbol == buyAsset.symbol {
                swapTransaction?.buyAssetTxnHash = swap.secretSeeker.receipt
            } else {
                swapTransaction?.sellAssetTxnHash = swap.secretSeeker.receipt
            }
            
            updateSwapTx()
        }
        // Swap Seeker Settled Event - Final step
        .on("swapSeekerSettled") { [weak self] _ in
            guard let self = self else { return }
            
            self.swapStatus = .holderSettled
            self.swapStatus = .withdrawing
            
            do {
                let liquidity = try awaitPromise(
                    self.sdk.withdraw(
                        chain: sellAsset.blockchainName,
                        symbol: sellAsset.symbol,
                        amount: BigInt(stringLiteral: sellAmount)
                    )
                )
                
                timeoutWorkItem?.cancel()
                
                // Success - update transaction
                self.swapStatus = .succeded
                self.swapTransaction?.status = .confirmed
                self.swapTransaction?.error = nil
                
                updateSwapTx()
                                
                if let transaction = self.swapTransaction {
                    resolve(transaction)
                } else {
                    reject(NSError(domain: "PortalSwapSDK", code: -3, userInfo: [NSLocalizedDescriptionKey: "Transaction is nil"]))
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    try? awaitPromise(self.stopSwapSdk())
                }
            } catch {
                self.swapTransaction?.status = .failed
                self.swapTransaction?.error = error.localizedDescription
                self.swapStatus = .failed("\(error)")
                
                updateSwapTx()
                
                timeoutWorkItem?.cancel()
                reject(error)
                
                try? awaitPromise(self.stopSwapSdk())
            }
        }
    }
    
    private func updateSwapTx() {
        guard let transaction = self.swapTransaction, let hash = transaction.hash else {
            return warn("swap tx/hash not found, can't save")
        }
        
        do {
            try sdk.store.update(hash: hash, transaction: transaction)
        } catch {
            warn("failed to save swap tx in db", error.localizedDescription)
        }
    }
    
    private func stopSwapSdk() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            try awaitPromise(sdk.stop())
        }
    }
    
    // Helper function to format units (equivalent to ethers.utils.formatUnits)
    private func formatUnits(_ value: BigInt, decimals: Int) -> String {
        let divisor = pow(10.0, Double(decimals))
        let doubleValue = Double(value.description) ?? 0
        return String(doubleValue / divisor)
    }
}
