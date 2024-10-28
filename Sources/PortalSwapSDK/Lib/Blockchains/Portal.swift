import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Portal: BaseClass {
    private let sdk: Sdk
    private let props: SwapSdkConfig.Blockchains.Portal
    private let portalChainId = EthereumQuantity.init(quantity: BigUInt(7070))
    
    private var web3WebSocketClient: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    
    private var web3RpcClient: Web3!
    
    private var admm: IAdmmContract?

    private var logsSubscriptionId: String? = nil
    private var connected = false
    
    var admmContractAddress: String?
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Portal) {
        self.sdk = sdk
        self.props = props
        super.init(id: "portal")
    }
        
    func connect() -> Promise<Void> {
        Promise { [unowned self] in
            websocketProvider = try Web3WebSocketProvider(wsUrl: props.url, timeout: .seconds(10*60))
            web3WebSocketClient = Web3(provider: websocketProvider)
            web3RpcClient = Web3(rpcURL: "http://node.playnet.portaldefi.zone:9545")
                            
            guard let contractAddressHex = admmContractAddress else {
                throw SwapSDKError.msg("ADMM contract data is missing")
            }
            
            let admmContractAddresIsEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
            let admmContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: admmContractAddresIsEipp55)
            
            admm = web3RpcClient.eth.Contract(type: ADMMContract.self, address: admmContractAddress)
            
            info("connect")
            emit(event: "connect")
            
            return connected = true
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            connected = false
            
            if let logsSubscriptionId {
                websocketProvider.unsubscribe(subscriptionId: logsSubscriptionId) { [weak self] success in
                    if !success {
                        self?.warn("Unable unsubscribe from logs", logsSubscriptionId)
                    } else {
                        self?.info("Unsubscribed from event subscription: \(logsSubscriptionId)")
                    }

                    let isClosed = self?.websocketProvider.webSocket.isClosed ?? true
                    
                    if !isClosed {
                        _ = self?.websocketProvider.webSocket.close(code: .goingAway)
                    }
                    
                    self?.websocketProvider = nil
                    self?.web3WebSocketClient = nil
                    self?.admm = nil
                    self?.logsSubscriptionId = nil
                    
                    resolve(())
                }
            }
        }
    }
    
    func createSwap(swapId: String, liquidityPoolId: String, secretHash: String, sellAsset: String, sellAmount: BigUInt, buyAsset: String, buyAmount: BigUInt, slippage: BigUInt) -> Promise<[String : String]> {
        Promise { [unowned self] resolve, _ in
            guard let order = sdk.dex.order else {
                throw SwapSDKError.msg("order is missing")
            }
            
            guard let admm, let admmContractAddress = admm.address else {
                throw SwapSDKError.msg("admm contract is missing")
            }
            
            let id = Data(hex: swapId)
            let liquidityPoolId = Data(hex: liquidityPoolId)
            let secretHash = Data(hex: secretHash)
            let swapCreation = BigUInt(0)
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            let buyId = "123456789"
            
            let (sellAsset, buyAsset) = try awaitPromise(retry(attempts: 3, delay: 3) { self.retriveNativeAddresses(order: order) })
            
            guard let sellAsset = EthereumAddress(hexString: sellAsset) else {
                throw SwapSDKError.msg("sell asset address isn't valid")
            }
            
            guard let buyAsset = EthereumAddress(hexString: buyAsset) else {
                throw SwapSDKError.msg("buy asset address isn't valid")
            }
            
            guard let swapOwner = EthereumAddress(hexString: privKey.address.hex(eip55: false)) else {
                throw SwapSDKError.msg("swap owner address isn't valid")
            }

            let status = "inactive"
            
            sdk.dex.secretHash = secretHash

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
            
            let nonce = try awaitPromise(retry(attempts: 3, delay: 3) { self.web3RpcClient.eth.getNonce(address: privKey.address) })
            let gasPrice = try awaitPromise(retry(attempts: 3, delay: 3) { self.web3RpcClient.eth.fetchGasPrice() })
            
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
                throw SwapSDKError.msg("failed to create swap transaction")
            }
                        
            let signedCreateSwapTx = try createSwapTx.sign(with: privKey, chainId: portalChainId)
            let txId = try awaitPromise(retry(attempts: 3, delay: 3) { self.web3RpcClient.eth.publish(transaction: signedCreateSwapTx) })
            
            debug("create swap tx hash: \(txId)")
                        
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 6, delay: 2) { self.web3RpcClient.eth.fetchReceipt(txHash: txIdData) })
            
            try subscribeToLogs(address: admmContractAddress)
            
            guard
                let log = receipt.logs.first,
                let swapCreatedEvent = try? ABI.decodeLog(event: ADMMContract.SwapCreated, from: log),
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
            else {
                guard connected else { return }
                return error("swap created logs error", ["unwrapping data failed"])
            }
                                    
            sdk.dex.swapId = swapId
            
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
                status: "inactive"
            )
            
            let receiptJson = [
                "from": createSwapTx.from?.hex(eip55: true) ?? "?",
                "to": createSwapTx.to?.hex(eip55: true) ?? "?",
                "blockHash": log.blockHash?.hex() ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded",
            ]
                        
            info("swap.created.event", [invoiceRegisteredEvent])
            info("swap.created.receipt", receiptJson)
            
            emit(event: "swap.created", args: [invoiceRegisteredEvent])
                        
            resolve(receiptJson)
        }
    }
    
    func registerInvoice(swapId: Data, secretHash: Data, amount: BigUInt, invoice: String) -> Promise<Response> {
        Promise { [unowned self] in
            guard let admm else {
                throw SwapSDKError.msg("admm contract isn missing")
            }
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            let nonce = try awaitPromise(retry(attempts: 3, delay: 3) { self.web3RpcClient.eth.getNonce(address: privKey.address) })
            
            debug("register invoice params", [
                "id": "0x\(swapId.hexString)",
                "secretHash": "0x\(secretHash.hexString)",
                "amount": amount.description,
                "invoice": invoice
            ])
                        
            let gasPrice = try awaitPromise(retry(attempts: 3, delay: 3) { self.web3RpcClient.eth.fetchGasPrice() })
            
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
                throw SwapSDKError.msg("failed to create register invoice tx")
            }
            
            let signedRegisterInvoiceTx = try registerInvoiceTx.sign(with: privKey, chainId: portalChainId)
            let txId = try awaitPromise(retry(attempts: 3, delay: 3) { self.web3RpcClient.eth.publish(transaction: signedRegisterInvoiceTx) })
            
            debug("register invoice tx hash: \(txId)")
            
            let receipt = [
                "from": registerInvoiceTx.from?.hex(eip55: true) ?? "?",
                "to": registerInvoiceTx.to?.hex(eip55: true) ?? "?",
                "transactionHash": txId
            ]
            
            return receipt
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
                        let sellAssetSymbol = self.sdk.blockchains.assetManagement.assets.first(where: {$0.id == sellAsset })?.symbol,
                        let buyAssetSymbol = self.sdk.blockchains.assetManagement.assets.first(where: {$0.id == buyAsset })?.symbol
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
}

extension Portal {
    private func subscribeToLogs(address: EthereumAddress) throws {
        let topics: [EthereumData] = [
            try EthereumData(ethereumValue: ADMMContract.SwapValidated.signature.sha3(.keccak256)),
            try EthereumData(ethereumValue: ADMMContract.SwapMatched.signature.sha3(.keccak256)),
            try EthereumData(ethereumValue: ADMMContract.InvoiceRegistered.signature.sha3(.keccak256))
        ]
        
        try web3WebSocketClient.eth.subscribeToLogs(addresses: [address], topics: [topics]) { [weak self] subscription in
            guard let self else { return }
            if let subscriptionId = subscription.result {
                logsSubscriptionId = subscriptionId
            } else if let subscriptionError = subscription.error {
                error("event logs subscription error", [subscriptionError])
            } else {
                warn("invalid subscription response", [subscription])
            }
        } onEvent: { [weak self] log in
            guard let self else { return }
            if let log = log.result {
                onEvent(log: log)
            } else if let logError = log.error {
                guard connected else { return }
                error("log error", [logError])
            } else {
                warn("event log invalid", [log])
            }
        }
    }
    
    private func onEvent(log: EthereumLogObject) {
        if let swapMatchedEvent = try? ABI.decodeLog(event: ADMMContract.SwapMatched, from: log) {
            guard
                let swapId = swapMatchedEvent["id"] as? Data,
                let liquidityOwner = swapMatchedEvent["liquidityOwner"] as? EthereumAddress,
                let sellAsset = swapMatchedEvent["sellAsset"] as? EthereumAddress,
                let matchedSellAmount = swapMatchedEvent["matchedSellAmount"] as? BigUInt,
                let matchedBuyAmount = swapMatchedEvent["matchedBuyAmount"] as? BigUInt
            else {
                guard connected else { return }
                return error("invoice created logs error", ["unwrapping data failed"])
            }
            
            guard sdk.dex.swapId == swapId else {
                return warn("received swap matched for swap with id \(swapId.hexString), current swapId \(sdk.dex.swapId?.hexString ?? "not set")")
            }
            
            let event = SwapMatchedEvent(
                swapId: swapId.hexString,
                liquidityOwner: liquidityOwner.hex(eip55: true),
                sellAsset: sellAsset.hex(eip55: true),
                matchedSellAmount: matchedSellAmount,
                matchedBuyAmount: matchedBuyAmount
            )
            
            info("swap.matched.event", [event])
            
            return emit(event: "swap.matched", args: [event])
        }
        
        if let swapValidatedEvent = try? ABI.decodeLog(event: ADMMContract.SwapValidated, from: log) {
            guard
                let swap = swapValidatedEvent["swap"] as? [Any],
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
                let buyId = swap[10] as? String,
                let status = swap[10] as? String
            else {
                guard connected else { return }
                return error("swap validated logs error", ["unwrapping data failed"])
            }
            
            guard sdk.dex.swapId == swapId else {
                return warn("received swap validated for swap with id \(swapId.hexString), current swapId \(sdk.dex.swapId?.hexString ?? "not set")")
            }
            
            let event = SwapValidatedEvent(
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
            
            return emit(event: "swap.validated", args: [event])
        }
        
        if let invoiceRegisteredEvent = try? ABI.decodeLog(event: ADMMContract.InvoiceRegistered, from: log) {
            guard
               let invoice = invoiceRegisteredEvent["invoice"] as? [Any],
               let swapId = invoice[0] as? Data,
               let secretHash = invoice[1] as? Data,
               let amount = invoice[2] as? BigUInt,
               let invoice = invoice[3] as? String
            else {
                guard connected else { return }
                return error("invoice registered logs error", ["unwrapping data failed"])
            }
            
            guard sdk.dex.swapId == swapId else {
                return warn("received invoice registered for swap with id \(swapId.hexString), current swapId \(sdk.dex.swapId?.hexString ?? "not set")")
            }
            
            let invoiceRegisteredEvent = InvoiceRegisteredEvent(
                swapId: swapId.hexString,
                secretHash: secretHash.hexString,
                amount: amount,
                invoice: invoice
            )
            
            let receipt = [
                "blockHash": log.blockHash?.hex() ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded",
            ]
                        
            let status = "lp.invoice.created"
            info(status, [invoiceRegisteredEvent])
            info("invoice.registered.receipt", receipt)
            
            return emit(event: status, args: [invoiceRegisteredEvent])
        }
        
        warn("Unknown log event", log)
    }
        
    private func retriveNativeAddresses(order: SwapOrder) -> Promise<(String, String)> {
        retry(attempts: 3, delay: 1) {
            all(
                self.retrieveAssetByNativeProps(
                    blockchainName: order.sellNetwork,
                    blockchainAddress: order.sellAddress
                ),
                self.retrieveAssetByNativeProps(
                    blockchainName: order.buyNetwork,
                    blockchainAddress: order.buyAddress
                )
            )
            .then { ($0, $1) }
        }
    }
    
    private func retrieveAssetByNativeProps(blockchainName: String, blockchainAddress: String) -> Promise<String> {
        sdk.blockchains.assetManagement.retrieveAssetByNativeProps(blockchainName: blockchainName, blockchainAddress: blockchainAddress).then { asset in
            guard let asset else {
                throw SwapSDKError.msg("Unknown asset: \(blockchainName), address: \(blockchainAddress)")
            }
            
            return asset.id.hex(eip55: true)
        }
    }
}
