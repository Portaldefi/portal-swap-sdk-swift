import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Portal: BaseClass {
    private let sdk: Sdk
    private let props: SwapSdkConfig.Blockchains.Portal
    private let portalChainId = EthereumQuantity.init(quantity: BigUInt(7070))
    
    private var web3: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    private var admm: IAdmmContract?

    private var subscriptionIds = [String]()
    private var connected = false
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Portal) {
        self.sdk = sdk
        self.props = props
        super.init(id: "portal")
    }
        
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                websocketProvider = try Web3WebSocketProvider(wsUrl: props.url)
                web3 = Web3(provider: websocketProvider)
                                
                //notaryADMM contract
                guard
                    let contract = props.contracts["NotaryADMM"] as? [String: Any],
                    let contractAddressHex = contract["address"] as? String
                else {
                    return reject(SwapSDKError.msg("ADMM contract data is missing"))
                }
                
                let admmContractAddresIsEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)                
                let admmContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: admmContractAddresIsEipp55)
                admm = web3.eth.Contract(type: ADMMContract.self, address: admmContractAddress)
                                
                guard let admm else {
                    return reject(SwapSDKError.msg("ADMM contract is missing"))
                }
                
                //notaryADMM contract subscriptions
                for (index, event) in admm.events.enumerated() {
                    let signatureHex = "0x\(Utils.keccak256Hash(of: event.signature))"
                    let addresses = [admmContractAddress]
                    let data = try EthereumData(ethereumValue: signatureHex)
                    let topics = [[data]]
                    
                    let request = RPCRequest<[LogsParam]>(
                        id: index + 1,
                        jsonrpc: Web3.jsonrpc,
                        method: "eth_subscribe",
                        params: [
                            LogsParam(params: nil),
                            LogsParam(params: LogsParam.Params(address: addresses, topics: topics))
                        ]
                    )
                    
                    switch event.name {
                    case ADMMContract.SwapValidated.name:
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionIds.append(subscriptionID)
                            case .failure(let error):
                                self.error("Swap validated subscription error", [error, event])
                            }
                        } onEvent: { [weak self] (response: Web3Response<SwapValidatedEvent>) in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                            }
                                                        
                            switch response.status {
                            case .success(let event):
                                info("swap.validated.event", [event])
                                emit(event: "swap.validated", args: [event])
                            case .failure(let error):
                                guard connected else { return }

                                self.error("Swap validated event error", [error])
                            }
                        }
                    case ADMMContract.SwapMatched.name:
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionIds.append(subscriptionID)
                            case .failure(let error):
                                self.error("swap matched subscription error", [error, event.name])
                            }
                        } onEvent: { [weak self] (response: Web3Response<SwapMatchedEvent>) in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                            }
                            
                            switch response.status {
                            case .success(let event):
                                self.info("swap.matched.event", [event])
                                self.emit(event: "swap.matched", args: [event])
                            case .failure(let error):
                                guard connected else { return }

                                self.error("Swap matched event error", [error])
                            }
                        }
                    default:
                        continue
                    }
                }
                                                            
                self.info("connect")
                self.emit(event: "connect")
                self.connected = true
                resolve(())
            } catch {
                self.error("connect", [error])
                self.connected = false
                reject(error)
            }
        }
    }

    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            connected = false
            
            for subscriptionsId in subscriptionIds {
                websocketProvider.unsubscribe(subscriptionId: subscriptionsId, completion: { _ in ()})
            }
            subscriptionIds.removeAll()
            
            guard !websocketProvider.webSocket.isClosed else {
                return resolve(())
            }
            
            websocketProvider.webSocket.close().whenComplete { [weak self] _ in
                guard let self = self else {
                    return reject(SwapSDKError.msg("Cannot weakly handle self"))
                }
                guard self.websocketProvider.closed else {
                    return reject(SwapSDKError.msg("Web socket isnt's closed"))
                }
                resolve(())
            }
        }
    }
        
    func registerInvoice(swapId: Data, secretHash: Data, amount: BigUInt, invoice: String) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let admm, let admmContractAddress = admm.address else {
                return reject(SwapSDKError.msg("admm contract isn missing"))
            }
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            let nonce = try awaitPromise(web3.eth.getNonce(address: privKey.address))
            
            debug("register invoice params", [
                "id": "0x\(swapId.hexString)",
                "secretHash": "0x\(secretHash.hexString)",
                "amount": amount.description,
                "invoice": invoice
            ])
                        
            let gasPrice = try awaitPromise(web3.eth.fetchGasPrice())
            
            guard let registerInvoiceTx = admm.registerInvoice(
                id: swapId,
                secretHash: secretHash,
                amount: amount,
                invoice: invoice
            ).createTransaction(
                nonce: nonce,
                gasPrice: gasPrice,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasLimit: EthereumQuantity(quantity: 600_000),
                from: privKey.address,
                value: EthereumQuantity(quantity: 0),
                accessList: [:],
                transactionType: .legacy
            ) else {
                self.error("register invoice tx failed error", [invoice])
                return reject(SwapSDKError.msg("register invoice tx failed to build"))
            }
            
            let signedRegisterInvoiceTx = try registerInvoiceTx.sign(with: privKey, chainId: portalChainId)
            let txId = try awaitPromise(web3.eth.publish(transaction: signedRegisterInvoiceTx))
            
            debug("register invoice tx hash: \(txId)")
            
            let topics = ADMMContract.InvoiceRegistered.topics()
            
            try web3.eth.subscribeToLogs(addresses: [admmContractAddress], topics: topics) { subscription in
                guard let error = subscription.error else {
                    guard let subscriptionId = subscription.result else { return }
                    return self.subscriptionIds.append(subscriptionId)
                }
                guard self.connected else { return }
                self.error("register invoice subscription", [error])
            } onEvent: { log in
                if let error = log.error {
                    guard self.connected else { return }
                    self.error("invoice.registered.event.error", [error])
                } else {
                    if let topicValue = log.result,
                       let invoiceRegisteredEvent = try? ABI.decodeLog(event: ADMMContract.InvoiceRegistered, from: topicValue),
                       let invoice = invoiceRegisteredEvent["invoice"] as? [Any],
                       let swapId = invoice[0] as? Data,
                       let secretHash = invoice[1] as? Data,
                       let amount = invoice[2] as? BigUInt,
                       let invoice = invoice[3] as? String
                    {
                        let logEvent = [
                            "swapId": "0x\(swapId.hexString)",
                            "secretHash": "0x\(secretHash.hexString)",
                            "amount": amount.description,
                            "invoice": invoice
                        ]
                        
                        let invoiceRegisteredEvent = InvoiceRegisteredEvent(
                            swapId: swapId.hexString,
                            secretHash: secretHash.hexString,
                            amount: amount,
                            invoice: invoice
                        )
                        
                        let receipt = [
                            "blockHash": topicValue.blockHash?.hex() ?? "?",
                            "from": registerInvoiceTx.from?.hex(eip55: true) ?? "?",
                            "to": registerInvoiceTx.to?.hex(eip55: true) ?? "?",
                            "transactionHash": topicValue.transactionHash?.hex() ?? "?",
                            "status": "succeeded",
                        ]
                        
                        let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                        
                        self.info("invoice.registered.event", [invoiceRegisteredEvent])
                        
                        resolve(mergedReceipt)
                    } else {
                        reject(SwapSDKError.msg("invoice.registered.event has no logs"))
                    }
                }
            }
        }
    }
    
    func createSwap(swapId: String, liquidityPoolId: String, secretHash: String, sellAsset: String, sellAmount: BigUInt, buyAsset: String, buyAmount: BigUInt, slippage: BigUInt) -> Promise<[String : String]> {
        Promise { [unowned self] resolve, reject in
            guard let order = sdk.dex.order else {
                return reject(SwapSDKError.msg("order is missing"))
            }
            
            guard let admm, let admmContractAddress = admm.address else {
                return reject(SwapSDKError.msg("admm contract is missing"))
            }
            
            let id = Data(hex: swapId)
            let liquidityPoolId = Data(hex: liquidityPoolId)
            let secretHash = Data(hex: secretHash)
            let swapCreation = BigUInt(0)
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            let buyId = "123456789"
            
            let (sellAsset, buyAsset) = try awaitPromise(retriveNativeAddresses(order: order))
            
            guard let sellAsset = EthereumAddress(hexString: sellAsset) else {
                return reject(SwapSDKError.msg("sell asset address isn't valid"))
            }
            
            guard let buyAsset = EthereumAddress(hexString: buyAsset) else {
                return reject(SwapSDKError.msg("buy asset address isn't valid"))
            }
            
            guard let swapOwner = EthereumAddress(hexString: privKey.address.hex(eip55: false)) else {
                return reject(SwapSDKError.msg("swap owner address isn't valid"))
            }

            let status = "inactive"
                    
            debug("create swap params", [
                "id": "0x\(id.hexString)",
                "liquidityPoolId": "0x\(liquidityPoolId.hexString)",
                "secretHash": "0x\(secretHash.hexString)",
                "sellAsset": sellAsset.hex(eip55: true),
                "sellAmount": sellAmount.description,
                "buyAsset": buyAsset.hex(eip55: true),
                "buyAmount": buyAmount.description,
                "swapOwner": swapOwner.hex(eip55: true),
                "buyId": buyId,
                "status": status
            ])
            
            let nonce = try awaitPromise(web3.eth.getNonce(address: privKey.address))
            let gasPrice = try awaitPromise(web3.eth.fetchGasPrice())
            
            guard let createSwapTx = admm.createSwap(
                id: id,
                liquidityPoolId: liquidityPoolId,
                secretHash: secretHash,
                sellAsset: sellAsset,
                sellAmount: sellAmount,
                buyAsset: buyAsset,
                buyAmount: buyAmount,
                slippage: slippage,
                swapCreation: swapCreation,
                swapOwner: swapOwner,
                buyId: buyId,
                status: status
            ).createTransaction(
                nonce: nonce,
                gasPrice: gasPrice,
                maxFeePerGas: nil,
                maxPriorityFeePerGas: nil,
                gasLimit: EthereumQuantity(quantity: 300_000),
                from: privKey.address,
                value: EthereumQuantity(quantity: 0),
                accessList: [:],
                transactionType: .legacy
            ) else {
                self.error("failed to create swap transaction", [
                    "id": "0x\(id.hexString)",
                    "liquidityPoolId": "0x\(liquidityPoolId.hexString)",
                    "secretHash": "0x\(secretHash.hexString)",
                    "sellAsset": sellAsset.hex(eip55: true),
                    "sellAmount": sellAmount.description,
                    "buyAsset": buyAsset.hex(eip55: true),
                    "buyAmount": buyAmount.description,
                    "swapOwner": swapOwner.hex(eip55: true),
                    "buyId": buyId,
                    "status": status
                ])
                return reject(SwapSDKError.msg("failed to create swap transaction"))
            }
            
            let signedCreateSwapTx = try createSwapTx.sign(with: privKey, chainId: portalChainId)
            let txId = try awaitPromise(web3.eth.publish(transaction: signedCreateSwapTx))
            
            debug("create swap tx hash: \(txId)")

            let topics = ADMMContract.SwapCreated.topics()
            
            try web3.eth.subscribeToLogs(addresses: [admmContractAddress], topics: topics) { subscription in
                guard let error = subscription.error else {
                    guard let subscriptionId = subscription.result else { return }
                    return self.subscriptionIds.append(subscriptionId)
                }
                guard self.connected else { return }
                self.error("swap created subscription", [error])
            } onEvent: { log in
                if let error = log.error {
                    guard self.connected else { return }
                    self.error("swap.created.event.error", [error])
                } else {
                    if let topicValue = log.result,
                       let swapCreatedEvent = try? ABI.decodeLog(event: ADMMContract.SwapCreated, from: topicValue),
                       let swap = swapCreatedEvent["swap"] as? [Any],
                       let swapId = swap[0] as? Data,
                       let liquidityPoolId = swap[1] as? Data,
                       let secretHash = swap[2] as? Data,
                       let sellAsset = swap[3] as? EthereumAddress,
                       let sellAmount = swap[4] as? BigUInt,
                       let buyAsset = swap[5] as? EthereumAddress,
                       let buyAmount = swap[6] as? BigUInt,
                       let slippage = swap[7] as? BigUInt,
                       let swapCreation = swap[8] as? BigUInt,
                       let swapOwner = swap[9] as? EthereumAddress,
                       let buyId = swap[10] as? String
                    {
                        let logEvent = [
                            "swapId": "0x\(swapId.hexString)",
                            "liquidityPoolId": "0x\(liquidityPoolId.hexString)",
                            "secretHash": "0x\(secretHash.hexString)",
                            "sellAsset": sellAsset.hex(eip55: true),
                            "sellAmount": sellAmount.description,
                            "buyAsset": buyAsset.hex(eip55: true),
                            "buyAmount": buyAmount.description,
                            "slippage": slippage.description,
                            "swapCreation": swapCreation.description,
                            "swapOwner": swapOwner.hex(eip55: true),
                            "buyId": buyId
                        ]
                        
                        let invoiceRegisteredEvent = SwapCreatedEvent(
                            swapId: swapId.hexString,
                            liquidityPoolId: liquidityPoolId.hexString,
                            secretHash: secretHash.hexString,
                            sellAsset: sellAsset.hex(eip55: true),
                            sellAmount: sellAmount,
                            buyAsset: buyAsset.hex(eip55: true),
                            buyAmount: buyAmount,
                            slippage: slippage,
                            swapCreation: swapCreation,
                            swapOwner: swapOwner.hex(eip55: true),
                            buyId: buyId,
                            status: status
                        )
                        
                        let receipt = [
                            "blockHash": topicValue.blockHash?.hex() ?? "?",
                            "from": createSwapTx.from?.hex(eip55: true) ?? "?",
                            "to": createSwapTx.to?.hex(eip55: true) ?? "?",
                            "transactionHash": topicValue.transactionHash?.hex() ?? "?",
                            "status": "succeeded",
                        ]
                        
                        let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                                                                                    
                        self.info("swap.created.event", [invoiceRegisteredEvent])
                        self.emit(event: "swap.created", args: [invoiceRegisteredEvent])
                        
                        resolve(mergedReceipt)
                    } else {
                        reject(SwapSDKError.msg("swap.created.event has no logs"))
                    }
                }
            }
        }
    }
    
    func getOutput(id: String) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let admm else {
                return reject(SwapSDKError.msg("admm contract isn missing"))
            }
            
            let id = Data(hex: id)
            
            admm.eventOutputs(id: id).call { response, error in
                if let response {
                    guard 
                        let matchedBuyAmount = (response["matchedBuyAmount"] as? BigUInt)?.description,
                        let invoice = response["invoice"] as? String
                    else {
                        return reject(SwapSDKError.msg("eventOutputs corupt"))
                    }
                    
                    resolve(
                        [
                            "matchedBuyAmount": matchedBuyAmount,
                            "invoice": invoice
                        ]
                    )
                } else if let error {
                    reject(error)
                } else {
                    reject(SwapSDKError.msg("get output id: \(id) unexpected response"))
                }
            }
        }
    }
    
    func getSwap(id: String) -> Promise<AmmSwap> {
        Promise { [unowned self] resolve, reject in
            guard let admm else {
                return reject(SwapSDKError.msg("admm contract isn missing"))
            }
                        
            let id = Data(hex: id)
            
            admm.getSwap(id: id).call { swap, error in
                if let swap {
                    guard
                        let swapId = swap["id"] as? Data,
                        let liquidityPoolId = swap["liquidityPoolId"] as? Data,
                        let secretHash = swap["secretHash"] as? Data,
                        let sellAsset = swap["sellAsset"] as? EthereumAddress,
                        let sellAmount = swap["sellAmount"] as? BigUInt,
                        let buyAsset = swap["buyAsset"] as? EthereumAddress,
                        let buyAmount = swap["buyAmount"] as? BigUInt,
                        let slippage = swap["slippage"] as? BigUInt,
                        let swapCreation = swap["swapCreation"] as? BigUInt,
                        let swapOwner = swap["swapOwner"] as? EthereumAddress,
                        let buyId = swap["buyId"] as? String,
                        let status = swap["status"] as? String
                    else {
                        return reject(SwapSDKError.msg("get swap, unexpected response"))
                    }
                    
                    guard
                        let sellAssetSymbol = self.sdk.assetManagement.assets.first(where: {$0.id == sellAsset })?.symbol,
                        let buyAssetSymbol = self.sdk.assetManagement.assets.first(where: {$0.id == buyAsset })?.symbol
                    else {
                        return reject(SwapSDKError.msg("Unknown assets"))
                    }
                    
                    let ammSwap = AmmSwap(
                        swapId: swapId,
                        secretHash: secretHash,
                        liquidityPoolId: liquidityPoolId,
                        sellAssetSymbol: sellAssetSymbol,
                        sellAsset: sellAsset,
                        sellAmount: sellAmount,
                        buyAssetSymbol: buyAssetSymbol,
                        buyAsset: buyAsset,
                        buyAmount: buyAmount,
                        slippage: slippage,
                        swapCreation: swapCreation,
                        swapOwner: swapOwner,
                        buyId: buyId,
                        status: status
                    )

                    resolve(ammSwap)
                } else if let error {
                    reject(error)
                } else {
                    reject(SwapSDKError.msg("get swap id: \(id) unexpected response"))
                }
            }
        }
    }
 }

extension Portal {
    private func sign(transaction: EthereumTransaction) throws -> EthereumSignedTransaction {
        let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
        return try transaction.sign(with: privKey, chainId: EthereumQuantity.string(props.chainId))
    }
    
    private func retriveNativeAddresses(order: SwapOrder) -> Promise<(String, String)> {
        Promise { [unowned self] resolve, _ in
            let sellAddress = try awaitPromise(
                retrieveAssetByNativeProps(
                    blockchainName: order.sellNetwork,
                    blockchainAddress: order.sellAddress
                )
            )
            let buyAddress = try awaitPromise(
                retrieveAssetByNativeProps(
                    blockchainName: order.buyNetwork,
                    blockchainAddress: order.buyAddress
                )
            )
            resolve((sellAddress, buyAddress))
        }
    }
    
    private func retrieveAssetByNativeProps(blockchainName: String, blockchainAddress: String) -> Promise<String> {
        Promise { [unowned self] resolve, reject in
            sdk.assetManagement.retrieveAssetByNativeProps(blockchainName: blockchainName, blockchainAddress: blockchainAddress).then { asset in
                guard let asset else {
                    return reject(SwapSDKError.msg("Unknown asset: \(blockchainName), address: \(blockchainAddress)"))
                }
                
                resolve(asset.id.hex(eip55: true))
            }.catch { retrieveAssetByNativePropsError in
                reject(retrieveAssetByNativePropsError)
            }
        }
    }
}
