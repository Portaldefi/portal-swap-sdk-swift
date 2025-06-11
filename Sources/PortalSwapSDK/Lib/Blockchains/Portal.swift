import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Portal: BaseClass {
    private let props: SwapSdkConfig.Blockchains.Portal
    
    private let web3: Web3!
    
    private var liquidityManager: ILiquidityManagerContract!
    private var assetManager: IAssetManagerContract!
    private var swapManager: ISwapManagerContract!
        
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
            
            let assetManagerContractAddress = try DynamicContract.contractAddress(address: props.assetManagerContractAddress)
            assetManager = web3.eth.Contract(type: AssetManagerContract.self, address: assetManagerContractAddress)
            
            let liquidityManagerContractAddress = try DynamicContract.contractAddress(address: props.liquidityManagerContractAddress)
            liquidityManager = web3.eth.Contract(type: LiquidityManagerContract.self, address: liquidityManagerContractAddress)
            
            liquidityManager.watchContractEvents(
                interval: 1,
                onLogs: { [weak self] logs in
                    self?.onLiquidityManagerLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Liquidity manager logs error", error)
                })
            
            let swapManagerContractAddress = try DynamicContract.contractAddress(address: props.swapManagerContractAddress)
            swapManager = web3.eth.Contract(type: SwapManagerContract.self, address: swapManagerContractAddress)
                
            swapManager.watchContractEvents(
                interval: 1,
                onLogs: { [weak self] logs in
                    self?.onSwapManagerLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Swap manager logs error", error)
                })
            
            let orderbookMarketContractAddress = try DynamicContract.contractAddress(address: props.orderbookMarketContractAddress)
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
            guard let self else { throw SwapSDKError.msg("portal is missing") }

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
            guard let self else { throw SwapSDKError.msg("portal is missing") }
            
            if !liquidity.isWithdrawal {
                throw SwapSDKError.msg("burn asset only for withdrawal")
            }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let nonce = try awaitPromise(web3.eth.getNonce(address: swapOwner))
            
            guard let tx = liquidityManager.burnAsset(liquidity: liquidity).createTransaction(
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
                        
            let privKey = try EthereumPrivateKey(hexPrivateKey: props.privKey)
            let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(props.chainId))
            
            let txId = try awaitPromise(web3.eth.publish(transaction: signedTx))
            debug("burn asset tx id", txId)
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchReceipt(txHash: txIdData) })
                                    
            debug("burn asset receipt", receipt)
                      
            var gotBurnedAssetEvent = false
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case LiquidityManagerContract.AssetBurned.topic0:
                    gotBurnedAssetEvent = true
                    break
                default:
                    continue
                }
            }
            
            guard gotBurnedAssetEvent else {
                throw SwapSDKError.msg("Failed to burn asset")
            }
        }
    }
    
    func registerInvoice(_ swap: Swap) -> Promise<Void> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let nonce = try awaitPromise(web3.eth.getNonce(address: swapOwner))
            
            guard let tx = swapManager.registerInvoice(swap).createTransaction(
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
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: props.privKey)
            let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(props.chainId))
            
            let txId = try awaitPromise(web3.eth.publish(transaction: signedTx))
            debug("register invoice tx id", txId)
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchReceipt(txHash: txIdData) })
                                    
            debug("register invoice receipt", receipt)
                      
            var gotInvoicedEvent = false
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case SwapManagerContract.SwapHolderInvoiced.topic0:
                    gotInvoicedEvent = true
                    break
                case SwapManagerContract.SwapSeekerInvoiced.topic0:
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
}

extension Portal {
    private func onLiquidityManagerLogs(_ logs: [EthereumLogObject]) {
        for log in logs {
            switch log.topics.first {
            case LiquidityManagerContract.AssetMinted.topic0:
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
            case LiquidityManagerContract.AssetBurned.topic0:
                if let assetBurnedEvent = try? ABI.decodeLog(event: LiquidityManagerContract.AssetBurned, from: log) {
//                    guard
//                        let id = assetBurnedEvent["id"] as? Data,
//                        let ts = assetBurnedEvent["ts"] as? BigUInt,
//                        let nativeAmount = assetBurnedEvent["nativeAmount"] as? BigUInt,
//                        let portalAmount = assetBurnedEvent["portalAmount"] as? BigUInt,
//                        let portalAddress = assetBurnedEvent["portalAddress"] as? String,
//                        let chain = assetBurnedEvent["chain"] as? String,
//                        let symbol = assetBurnedEvent["symbol"] as? String,
//                        let contractAddress = assetBurnedEvent["contractAddress"] as? String,
//                        let nativeAddress = assetBurnedEvent["nativeAddress"] as? String
//                    else {
//                        guard connected else { return }
//                        return error("asset burned logs error", ["unwrapping data failed"])
//                    }
//
//                    let event = AssetBurnedEvent(
//                        id: id,
//                        ts: ts,
//                        nativeAmount: nativeAmount,
//                        portalAmount: portalAmount,
//                        portalAddress: portalAddress,
//                        chain: chain,
//                        symbol: symbol,
//                        contractAddress: contractAddress,
//                        nativeAddress: nativeAddress
//                    )
//
//                    info("liquidity.asset.burned.event", [event])
//                    emit(event: "liquidity.asset.burned", args: [event])
                }
            default:
                break
            }
        }
    }
    
    private func onSwapManagerLogs(_ logs: [EthereumLogObject]) {
        for log in logs {
            guard let topic = log.topics.first else { return }
            
            switch topic {
            case SwapManagerContract.SwapMatched.topic0:
                do {
                    let json = try ABI.decodeLog(event: SwapManagerContract.SwapMatched, from: log)
                    let swap = try Swap(json: json)
                    
                    info("swap.matched.event", [swap.toJSON()])
                    emit(event: "swapMatched", args: [swap])
                } catch {
                    guard connected else { return }
                    self.error("swap matched logs error", ["unwrapping data failed": error])
                }
            case SwapManagerContract.SwapSeekerInvoiced.topic0:
                do {
                    let json = try ABI.decodeLog(event: SwapManagerContract.SwapSeekerInvoiced, from: log)
                    let swap = try Swap(json: json)
                    
                    info("swap.seeker.invoiced.event", [swap.toJSON()])
                    emit(event: "swapSeekerInvoiced", args: [swap])
                } catch {
                    guard connected else { return }
                    self.error("SwapSeekerInvoiced error", ["unwrapping data failed": error])
                }
            case SwapManagerContract.SwapHolderInvoiced.topic0:
                do {
                    let json = try ABI.decodeLog(event: SwapManagerContract.SwapHolderInvoiced, from: log)
                    let swap = try Swap(json: json)
                    
                    info("swap.holder.invoiced.event", [swap.toJSON()])
                    emit(event: "swapHolderInvoiced", args: [swap])
                } catch {
                    guard connected else { return }
                    self.error("SwapHolderInvoiced error", ["unwrapping data failed": error])
                }
            default:
                return
            }
        }
    }
}
