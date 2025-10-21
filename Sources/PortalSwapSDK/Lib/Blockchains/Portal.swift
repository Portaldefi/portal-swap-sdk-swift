import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Portal: BaseClass {
    private let props: SwapSdkConfig.Blockchains.Portal
    
    private let web3: Web3!
    
    var queue = TransactionLock()
    
    private var liquidityManager: ILiquidityManagerContract!
    private var assetManager: IAssetManagerContract!
    private var swapManager: ISwapManagerContract!
    private var orderbookMarket: IOrderbookMarketContract!
    private var portalTransfer: IPortalTransferContract!
            
    private var connected = false
    
    var address: String {
        props.userAddress
    }
    
    init(props: SwapSdkConfig.Blockchains.Portal) {
        self.props = props
        
        web3 = Web3(rpcURL: props.rpcUrl)
        
        let orderbookMarketContractAddress = try! DynamicContract.address(props.orderbookMarketContractAddress)
        orderbookMarket = web3.eth.Contract(type: OrderbookMarketContract.self, address: orderbookMarketContractAddress)
        
        let assetManagerContractAddress = try! DynamicContract.address(props.assetManagerContractAddress)
        assetManager = web3.eth.Contract(type: AssetManagerContract.self, address: assetManagerContractAddress)
        
        let liquidityManagerContractAddress = try! DynamicContract.address(props.liquidityManagerContractAddress)
        liquidityManager = web3.eth.Contract(type: LiquidityManagerContract.self, address: liquidityManagerContractAddress)
        
        let swapManagerContractAddress = try! DynamicContract.address(props.swapManagerContractAddress)
        swapManager = web3.eth.Contract(type: SwapManagerContract.self, address: swapManagerContractAddress)
        
        let portalTransferContractAddress = try! DynamicContract.address("0x0000000000000000000000000000000000001000")
        portalTransfer = web3.eth.Contract(type: PortalTransferContract.self, address: portalTransferContractAddress)
        
        super.init(id: "portal")
    }
    
    func start() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            liquidityManager.watchContractEvents(
                interval: 5,
                onLogs: { [weak self] logs in
                    self?.onLiquidityManagerLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Liquidity manager logs error", error)
                })
                
            swapManager.watchContractEvents(
                interval: 5,
                onLogs: { [weak self] logs in
                    self?.onSwapManagerLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Swap manager logs error", error)
                })
            
            info("start")
            emit(event: "start")
            
            connected = true
            
            debug("started")
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }

            connected = false
            
            liquidityManager.stopWatchingContractEvents()
            swapManager.stopWatchingContractEvents()
            
            debug("stopped")
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
                                    
            debug("burn asset receipt status", receipt.status ?? "unknown")
                      
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

            debug("register invoice receipt", receipt.status ?? "unknown")
                      
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
    
    func getOrderLimits(assetId: String) -> Promise<(min: BigUInt, max: BigUInt)> {
        Promise { [weak self] resolve, reject in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
            
            orderbookMarket.getOrderLimits(assetId: assetId).call { result, error in
                if let min = result?["minAmount"] as? BigUInt, let max = result?["maxAmount"] as? BigUInt {
                    resolve((min: min, max: max))
                } else if let error {
                    reject(error)
                } else {
                    reject(SwapSDKError.msg("failed to get order limits") )
                }
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
                    
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            debug("open order tx id", txId)
            order.id = txId
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))

            debug("open order receipt: \(String(describing: receipt.status))")
                      
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
    
    func transfer(dstChain: String, receiver: EthereumAddress, amount: String, dstContract: EthereumAddress, message: Data) -> Promise<Bool> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.portalTransfer.transfer(
                        dstChain: dstChain,
                        receiver: receiver,
                        amount: amount,
                        dstContract: dstContract,
                        message: message
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
                        throw NativeChainError.init(message: "Failed to create transfer transaction", code: "404")
                    }
                    
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            debug("transfer tx id", txId)
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))

            debug("transfer receipt: \(String(describing: receipt.status))")
                                  
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case OrderbookMarketContract.OrderCreated.topic:
                    return true
                default:
                    continue
                }
            }
            
            return false
        }
    }
}

extension Portal {
    private func onLiquidityManagerLogs(_ logs: [EthereumLogObject]) {
        for log in logs {
            guard let txHash = log.transactionHash else { continue }

            switch log.topics.first {
            case LiquidityManagerContract.AssetMinted.topic:
                try? awaitPromise(waitForReceipt(txid: txHash.hex()))

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
                try? awaitPromise(waitForReceipt(txid: txHash.hex()))

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
            guard let txHash = log.transactionHash else { continue }
            
            switch topic {
            case SwapManagerContract.SwapMatched.topic:
                do {
                    try awaitPromise(waitForReceipt(txid: txHash.hex()))

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
                    try awaitPromise(waitForReceipt(txid: txHash.hex()))

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
                    try awaitPromise(waitForReceipt(txid: txHash.hex()))

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

extension Portal: TxLockable {
    internal func waitForReceipt(txid: String) -> Promise<Void> {
        Promise { [weak self] resolve, reject in
            guard let self else { throw SdkError.instanceUnavailable() }

            let txId = try EthereumData(ethereumValue: txid)
            
            waitForReceipt(hash: txId).then { _ in
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
    
    private func waitForReceipt(hash: EthereumData) -> Promise<EthereumTransactionReceiptObject> {
        retry(attempts: 10, delay: 3) {
            Promise {
                let confirmations: BigUInt = 1
                let receipt = try awaitPromise(retry(attempts: 10, delay: 3) { self.web3.eth.fetchReceipt(txHash: hash) })
                let head = try awaitPromise(retry(attempts: 10, delay: 3) { self.web3.eth.blockNumber() })
                
                guard head.quantity >= receipt.blockNumber.quantity + confirmations else {
                    throw SdkError(message: "Not confirmed yet", code: String())
                }
                
                return receipt
            }
        }
    }
}
