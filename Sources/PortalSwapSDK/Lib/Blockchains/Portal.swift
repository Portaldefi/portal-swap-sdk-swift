import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Portal: BaseClass {
    private let props: SwapSdkConfig.Blockchains.Portal
    
    private let web3: Web3!
    
    private var queue = TransactionLock()
    
    private var liquidityManager: ILiquidityManagerContract!
    private var assetManager: IAssetManagerContract!
    private var swapManager: ISwapManagerContract!
    private var orderbookMarket: IOrderbookMarketContract!
            
    private var connected = false
    
    var address: String {
        props.userAddress
    }
    
    init(props: SwapSdkConfig.Blockchains.Portal) {
        self.props = props
        
        web3 = Web3(rpcURL: props.rpcUrl)
        
        super.init(id: "portal")
    }
    
    func start() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            let assetManagerContractAddress = try DynamicContract.address(props.assetManagerContractAddress)
            assetManager = web3.eth.Contract(type: AssetManagerContract.self, address: assetManagerContractAddress)
            
            let liquidityManagerContractAddress = try DynamicContract.address(props.liquidityManagerContractAddress)
            liquidityManager = web3.eth.Contract(type: LiquidityManagerContract.self, address: liquidityManagerContractAddress)
            
            liquidityManager.watchContractEvents(
                interval: 3,
                onLogs: { [weak self] logs in
                    self?.onLiquidityManagerLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Liquidity manager logs error", error)
                })
            
            let swapManagerContractAddress = try DynamicContract.address(props.swapManagerContractAddress)
            swapManager = web3.eth.Contract(type: SwapManagerContract.self, address: swapManagerContractAddress)
                
            swapManager.watchContractEvents(
                interval: 3,
                onLogs: { [weak self] logs in
                    self?.onSwapManagerLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Swap manager logs error", error)
                })
            
            let orderbookMarketContractAddress = try DynamicContract.address(props.orderbookMarketContractAddress)
            orderbookMarket = web3.eth.Contract(type: OrderbookMarketContract.self, address: orderbookMarketContractAddress)
            
            info("start")
            emit(event: "start")
            
            connected = true
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }

            connected = false
            
            liquidityManager.stopWatchingContractEvents()
            swapManager.stopWatchingContractEvents()
        }
    }
    
    func retrieveAsset(chain: String, symbol: String) -> Promise<Asset> {
        Promise { [weak self] resolve, reject in
            guard let self else { throw SdkError.instanceUnavailable() }

            assetManager.retrieveAsset(chain: chain, symbol: symbol).call { result, error in
                if let result, let asset = try? Asset.fromSolidityValues(result) {
                    resolve(asset)
                } else if let error {
                    reject(error)
                } else {
                    reject(SwapSDKError.msg("failed to retrieve asset"))
                }
            }
        }
    }
    
    func burnAsset(_ liquidity: Liquidity) -> Promise<Liquidity> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            if !liquidity.isWithdrawal {
                throw SwapSDKError.msg("burn asset only for withdrawal")
            }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.liquidityManager.burnAsset(liquidity: liquidity).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 1_000_000),
                        from: swapOwner,
                        value: EthereumQuantity(quantity: 0),
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        throw SwapSDKError.msg("failed to create burn asset transaction")
                    }
                                
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            debug("burn asset tx id", txId)
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
                                    
            debug("burn asset receipt", receipt)
                      
            var gotBurnedAssetEvent = false
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case LiquidityManagerContract.AssetBurned.topic:
                    gotBurnedAssetEvent = true
                    break
                default:
                    continue
                }
            }
            
            guard gotBurnedAssetEvent else {
                throw SwapSDKError.msg("Failed to burn asset")
            }
            
            return liquidity
        }
    }
    
    func registerInvoice(_ swap: Swap) -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.swapManager.registerInvoice(swap).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 1_000_000),
                        from: swapOwner,
                        value: EthereumQuantity(quantity: 0),
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        throw NativeChainError.init(message: "Failed to create deposit transaction", code: "404")
                    }
                    
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })

            debug("register invoice tx id", txId)
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))

            debug("register invoice receipt", receipt)
                      
            var gotInvoicedEvent = false
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case SwapManagerContract.SwapHolderInvoiced.topic:
                    gotInvoicedEvent = true
                    break
                case SwapManagerContract.SwapSeekerInvoiced.topic:
                    gotInvoicedEvent = true
                    break
                default:
                    continue
                }
            }
            
            guard gotInvoicedEvent else {
                throw SwapSDKError.msg("Failed to register invoice")
            }
        }
    }
    
    func openOrder(_ order: Order) -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    print("Got nonce: \(nonce)")
                    
                    guard let tx = self.orderbookMarket.openOrder(
                        sellAsset: order.sellAsset,
                        sellAmount: order.sellAmount,
                        buyAsset: order.buyAsset,
                        buyAmount: order.buyAmount,
                        orderType: order.orderType
                    ).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 1_000_000),
                        from: swapOwner,
                        value: EthereumQuantity(quantity: 0),
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        print("Failed to create transaction")
                        throw NativeChainError.init(message: "Failed to create open order transaction", code: "404")
                    }
                    
                    print("Created transaction, signing...")
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    print("Publishing transaction...")
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            debug("open order tx id", txId)
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchReceipt(txHash: txIdData) })
                                    
            debug("open order receipt: \(receipt)")
                      
            var gotOpenOrderEvent = false
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case OrderbookMarketContract.OrderCreated.topic:
                    gotOpenOrderEvent = true
                    break
                default:
                    continue
                }
            }
            
            guard gotOpenOrderEvent else {
                throw SwapSDKError.msg("Failed to open order")
            }
        }
    }
}

extension Portal {
    private func onLiquidityManagerLogs(_ logs: [EthereumLogObject]) {
        for log in logs {
            switch log.topics.first {
            case LiquidityManagerContract.AssetMinted.topic:
                if let assetMintedEvent = try? ABI.decodeLog(event: LiquidityManagerContract.AssetMinted, from: log),
                   let liquidityObj = assetMintedEvent["liquidity"] as? [Any],
                   let liquidity = Liquidity.fromSolidityValues(liquidityObj)
                {
                    info("liquidity.asset.minted.event", [liquidity])
                    emit(event: "AssetMinted", args: [liquidity])
                } else {
                    guard connected else { return }
                    return error("asset minted logs error", ["unwrapping data failed"])
                }
            case LiquidityManagerContract.AssetBurned.topic:
                if let assetBurnedEvent = try? ABI.decodeLog(event: LiquidityManagerContract.AssetBurned, from: log) {
                    guard
                        let liquidityObj = assetBurnedEvent["liquidity"] as? [Any],
                        let liquidity = Liquidity.fromSolidityValues(liquidityObj)
                    else {
                        guard connected else { return }
                        return error("asset burned logs error", ["unwrapping data failed"])
                    }

                    info("liquidity.asset.burned.event", [liquidity])
                    emit(event: "AssetBurned", args: [liquidity])
                }
            default:
                break
            }
        }
    }
    
    private func onSwapManagerLogs(_ logs: [EthereumLogObject]) {
        for log in logs {
            guard let topic = log.topics.first else { return }
            
            DispatchQueue.sdk.asyncAfter(deadline: .now() + 1) {
                switch topic {
                case SwapManagerContract.SwapMatched.topic:
                    do {
                        let json = try ABI.decodeLog(event: SwapManagerContract.SwapMatched, from: log)
                        let swap = try Swap(json: json)
                        
                        self.info("swap.matched.event", [swap.toJSON()])
                        self.emit(event: "swapMatched", args: [swap])
                    } catch {
                        guard self.connected else { return }
                        self.error("swap matched logs error", ["unwrapping data failed": error])
                    }
                case SwapManagerContract.SwapSeekerInvoiced.topic:
                    do {
                        let json = try ABI.decodeLog(event: SwapManagerContract.SwapSeekerInvoiced, from: log)
                        let swap = try Swap(json: json)
                        
                        self.info("swap.seeker.invoiced.event", [swap.toJSON()])
                        self.emit(event: "swapSeekerInvoiced", args: [swap])
                    } catch {
                        guard self.connected else { return }
                        self.error("SwapSeekerInvoiced error", ["unwrapping data failed": error])
                    }
                case SwapManagerContract.SwapHolderInvoiced.topic:
                    do {
                        let json = try ABI.decodeLog(event: SwapManagerContract.SwapHolderInvoiced, from: log)
                        let swap = try Swap(json: json)
                        
                        self.info("swap.holder.invoiced.event", [swap.toJSON()])
                        self.emit(event: "swapHolderInvoiced", args: [swap])
                    } catch {
                        guard self.connected else { return }
                        self.error("SwapHolderInvoiced error", ["unwrapping data failed": error])
                    }
                default:
                    return
                }
            }
        }
    }
    
    private func withTxLock<T>(_ asyncFn: @escaping () -> Promise<T>) -> Promise<T> {
        queue.run(asyncFn)
    }
    
    private func emitOnFinality(txid: EthereumData, event: String, args: Any...) -> Promise<Void> {
        waitForReceipt(hash: txid).then { _ in
            let capitalizedEvent = "on\(event.prefix(1).uppercased())\(event.dropFirst())"
            self.info(capitalizedEvent, args)
            self.emit(event: event, args: args)
            return ()
        }
    }
    
    private func waitForReceipt(hash: EthereumData) -> Promise<EthereumTransactionReceiptObject> {
        retryWithBackoff { self.web3.eth.fetchReceipt(txHash: hash) }
    }
    
    private func retryWithBackoff<T>(_ fn: @escaping () -> Promise<T>) -> Promise<T> {
        Promise<T> { resolve, reject in
            let stages = [
                [1, 0], // 1 attempt immediately
                [10, 1000], // 10 attempts every 1 second
                // [10, 2000], // 10 attempts every 2 seconds
                // [10, 3000], // 10 attempts every 3 seconds
            ]
            
            func tryNextStage(stageIndex: Int) {
                guard stageIndex < stages.count else {
                    // All retries exhausted, try one final time to get the actual error
                    fn().then { result in
                        resolve(result)
                    }.catch { error in
                        reject(error)
                    }
                    return
                }
                
                let stage = stages[stageIndex]
                let attempts = stage[0]
                let delay = stage[1]
                
                func tryAttempt(attemptIndex: Int) {
                    fn().then { result in
                        resolve(result)
                    }.catch { error in
                        if attemptIndex == attempts - 1 {
                            // Last attempt of this stage, continue to next stage
                            tryNextStage(stageIndex: stageIndex + 1)
                        } else {
                            // More attempts in this stage
                            if delay > 0 {
                                DispatchQueue.sdk.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                                    tryAttempt(attemptIndex: attemptIndex + 1)
                                }
                            } else {
                                tryAttempt(attemptIndex: attemptIndex + 1)
                            }
                        }
                    }
                }
                
                tryAttempt(attemptIndex: 0)
            }
            
            tryNextStage(stageIndex: 0)
        }
    }
}
