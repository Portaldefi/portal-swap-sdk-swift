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

    private var logsSubscriptionId: String? = nil
    private var connected = false
    
    private var secretHash: Data? = nil
    private(set) var swapId: Data? = nil
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Portal) {
        self.sdk = sdk
        self.props = props
        super.init(id: "portal")
    }
        
    func connect() -> Promise<Void> {
        Promise { [unowned self] in
            websocketProvider = try Web3WebSocketProvider(wsUrl: props.url, timeout: .seconds(5*60))
            web3 = Web3(provider: websocketProvider)
                            
            guard
                let contract = props.contracts["NotaryADMM"] as? [String: Any],
                let contractAddressHex = contract["address"] as? String
            else {
                throw SwapSDKError.msg("ADMM contract data is missing")
            }
            
            let admmContractAddresIsEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
            let admmContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: admmContractAddresIsEipp55)
            
            admm = web3.eth.Contract(type: ADMMContract.self, address: admmContractAddress)
            
            try subscribeToLogs(address: admmContractAddress)
                                  
            info("connect")
            emit(event: "connect")
            
            return connected = true
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            connected = false
            swapId = nil
            secretHash = nil
            
            if let logsSubscriptionId {
                websocketProvider.unsubscribe(subscriptionId: logsSubscriptionId, completion: { _ in ()})
            }
            
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
    
    func createSwap(swapId: String, liquidityPoolId: String, secretHash: String, sellAsset: String, sellAmount: BigUInt, buyAsset: String, buyAmount: BigUInt, slippage: BigUInt) -> Promise<[String : String]> {
        Promise { [unowned self] in
            guard let order = sdk.dex.order else {
                throw SwapSDKError.msg("order is missing")
            }
            
            guard let admm else {
                throw SwapSDKError.msg("admm contract is missing")
            }
            
            let id = Data(hex: swapId)
            let liquidityPoolId = Data(hex: liquidityPoolId)
            let secretHash = Data(hex: secretHash)
            let swapCreation = BigUInt(0)
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            let buyId = "123456789"
            
            let (sellAsset, buyAsset) = try awaitPromise(retry(attempts: 3, delay: 2) { self.retriveNativeAddresses(order: order) })
            
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
            
            self.secretHash = secretHash

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
            
            let nonce = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.getNonce(address: privKey.address) })
            let gasPrice = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchGasPrice() })
            
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
            let txId = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.publish(transaction: signedCreateSwapTx) })
            
            debug("create swap tx hash: \(txId)")
            
            let receipt = [
                "from": createSwapTx.from?.hex(eip55: true) ?? "?",
                "to": createSwapTx.to?.hex(eip55: true) ?? "?",
                "transactionHash": txId
            ]
            
            return receipt
        }
    }
    
    func registerInvoice(swapId: Data, secretHash: Data, amount: BigUInt, invoice: String) -> Promise<Response> {
        Promise { [unowned self] in
            guard let admm else {
                throw SwapSDKError.msg("admm contract isn missing")
            }
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            let nonce = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.getNonce(address: privKey.address) })
            
            debug("register invoice params", [
                "id": "0x\(swapId.hexString)",
                "secretHash": "0x\(secretHash.hexString)",
                "amount": amount.description,
                "invoice": invoice
            ])
                        
            let gasPrice = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchGasPrice() })
            
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
            let txId = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.publish(transaction: signedRegisterInvoiceTx) })
            
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
            try EthereumData(ethereumValue: ADMMContract.SwapCreated.signature.sha3(.keccak256)),
            try EthereumData(ethereumValue: ADMMContract.SwapValidated.signature.sha3(.keccak256)),
            try EthereumData(ethereumValue: ADMMContract.SwapMatched.signature.sha3(.keccak256)),
            try EthereumData(ethereumValue: ADMMContract.InvoiceRegistered.signature.sha3(.keccak256))
        ]
        
        try web3.eth.subscribeToLogs(addresses: [address], topics: [topics]) { [unowned self] subscription in
            if let subscriptionId = subscription.result {
                logsSubscriptionId = subscriptionId
            } else if let error = subscription.error {
                self.error("event logs subscription error", [error])
            } else {
                warn("invalid subscription response", [subscription])
            }
        } onEvent: { [unowned self] log in
            if let log = log.result {
                onEvent(log: log)
            } else if let error = log.error {
                guard connected else { return }
                self.error("log error", [error])
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
            
            guard self.swapId == swapId || sdk.blockchains.ethereum.currentSwapId == swapId else {
                return warn("received swap matched, current swapId not matches swapId")
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
            
            guard self.swapId == swapId || sdk.blockchains.ethereum.currentSwapId == swapId else {
                return warn("received swap validated, current swapId not matches swapId")
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
            
            return info("swap.validated.event", [event])
        }
        
        if let swapCreatedEvent = try? ABI.decodeLog(event: ADMMContract.SwapCreated, from: log) {
            guard
                let swap = swapCreatedEvent["swap"] as? [Any],
                let swapId = swap[0] as? Data,
                let liquidityPoolId = swap[1] as? Data,
                let _secretHash = swap[2] as? Data,
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
            
            guard self.swapId == nil && secretHash == _secretHash else {
                return info("Received swap created event with unknown swapId")
            }
            
            debug("currentSwapId set", swapId.hexString)
            
            self.swapId = swapId
            
            let logEvent = [
                "swapId": "0x\(swapId.hexString)",
                "liquidityPoolId": "0x\(liquidityPoolId.hexString)",
                "secretHash": "0x\(secretHash!.hexString)",
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
                secretHash: secretHash!.hexString,
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
            
            let receipt = [
                "blockHash": log.blockHash?.hex() ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded",
            ]
            
            let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
            
            info("swap.created.event", [invoiceRegisteredEvent])
            info("swap.created.receipt", mergedReceipt)
            
            return emit(event: "swap.created", args: [invoiceRegisteredEvent])
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
            
            guard self.swapId == swapId || sdk.blockchains.ethereum.currentSwapId == swapId else {
                return warn("received invoice registered, current swapId not matches swapId")
            }
            
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
                "blockHash": log.blockHash?.hex() ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded",
            ]
            
            let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
            info("invoice.registered.receipt", mergedReceipt)

            return info("invoice.registered.event", [invoiceRegisteredEvent])
        }
        
        warn("Unknown log event", log)
    }
        
    private func retriveNativeAddresses(order: SwapOrder) -> Promise<(String, String)> {
        retry(attempts: 3, delay: 2) {
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
        sdk.assetManagement.retrieveAssetByNativeProps(blockchainName: blockchainName, blockchainAddress: blockchainAddress).then { asset in
            guard let asset else {
                throw SwapSDKError.msg("Unknown asset: \(blockchainName), address: \(blockchainAddress)")
            }
            
            return asset.id.hex(eip55: true)
        }
    }
}
