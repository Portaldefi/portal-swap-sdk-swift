import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Ethereum: BaseClass, IBlockchain {
    private let sdk: Sdk
    private let props: SwapSdkConfig.Blockchains.Ethereum
    
    private var web3: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    private var dexContract: IDexContract?
    private var liquidityProvider: ILiquidityProviderContract?
    
    private var subscriptionsIds = [String]()
    private var connected = false
    
    private(set) var currentSwapId: Data? = nil
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Ethereum) {
        self.sdk = sdk
        self.props = props
        super.init(id: "ethereum")
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                websocketProvider = try Web3WebSocketProvider(wsUrl: props.url, timeout: .seconds(5*60))
                web3 = Web3(provider: websocketProvider)
                
                //dex contract
                
                guard
                    let contract = props.contracts["Dex"] as? [String: Any],
                    let contractAddressHex = contract["address"] as? String
                else {
                    return reject(SwapSDKError.msg("Ethereum cannot prepare contract"))
                }
                
                let dexContractAddresisEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
                let dexContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: dexContractAddresisEipp55)
                
                dexContract = web3.eth.Contract(type: DexContract.self, address: dexContractAddress)
                
                //liquidity provider contract
                
                guard
                    let contract = props.contracts["LiquidityProvider"] as? [String: Any],
                    let contractAddressHex = contract["address"] as? String
                else {
                    return reject(SwapSDKError.msg("Ethereum cannot prepare contract"))
                }
                
                let lpAddresisEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
                let lpContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: lpAddresisEipp55)
                
                liquidityProvider = web3.eth.Contract(type: LiquidityProvider.self, address: lpContractAddress)
                                
                let topics = LiquidityProvider.InvoiceCreated.topics()
                
                try web3.eth.subscribeToLogs(addresses: [lpContractAddress], topics: topics) { subscription in
                    guard let error = subscription.error else {
                        guard let subscriptionId = subscription.result else { return }
                        return self.subscriptionsIds.append(subscriptionId)
                    }
                    guard self.connected else { return }
                    self.error("InvoiceCreated subscription error", [error])
                } onEvent: { log in
                    guard let error = log.error else {
                        guard
                            let topicValue = log.result,
                            let invoiceCreatedEvent = try? ABI.decodeLog(event: LiquidityProvider.InvoiceCreated, from: topicValue),
                            let swapId = invoiceCreatedEvent["swapId"] as? Data,
                            let swapOwner = invoiceCreatedEvent["swapOwner"] as? EthereumAddress,
                            let counterParty = invoiceCreatedEvent["counterParty"] as? EthereumAddress,
                            let sellAsset = invoiceCreatedEvent["sellAsset"] as? EthereumAddress,
                            let sellAmount = invoiceCreatedEvent["sellAmount"] as? BigUInt
                        else {
                            guard self.connected else { return }
                            return self.error("invoice created logs error", ["unwrapping data failed"])
                        }
                        
                        let publicAddress = try? self.publicAddress()
                        
                        guard self.currentSwapId == swapId || self.sdk.blockchains.portal.currentSwapId == swapId || publicAddress == counterParty else {
                            return self.warn("received lp InvoiceCreated event, publicAddress not equal counter party")
                        }
                        
                        self.currentSwapId = swapId
                        
                        let event = InvoiceCreatedEvent(
                            swapId: swapId.hexString,
                            swapOwner: swapOwner.hex(eip55: true),
                            counterParty: counterParty.hex(eip55: true),
                            sellAsset: sellAsset.hex(eip55: true),
                            sellAmount: sellAmount
                        )
                        
                        let status = "lp.invoice.created"
                        
                        self.info("swap status updated", [
                            "status": status,
                            "event": event
                        ])
                        
                        return self.emit(event: status, args: [event])
                    }
                    guard self.connected else { return }
                    self.error("lp invoice error", [error])
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
            currentSwapId = nil
            
            for subscriptionsId in subscriptionsIds {
                websocketProvider.unsubscribe(subscriptionId: subscriptionsId, completion: { _ in ()})
            }
            subscriptionsIds.removeAll()
            
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
    
    func swapOrder(secretHash: Data, order: SwapOrder) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let dexContract, let dexContractAddress = dexContract.address else {
                return reject(SwapSDKError.msg("Dex contract is nil"))
            }
            
            guard let sellAsset = EthereumAddress(hexString: order.sellAddress) else {
                return reject(SwapSDKError.msg("Cannot unwrap sell asset address"))
            }
            
            let swapOwner = try publicAddress()
            let nonce = try awaitPromise(web3.eth.getNonce(address: swapOwner))
            let quantity = EthereumQuantity(quantity: order.sellAmount)
            
            debug("swap order params", [
                "secretHash": "0x\(secretHash.hexString)",
                "sellAsset": sellAsset.hex(eip55: true),
                "sellAmount": order.sellAmount.description,
                "swapOwner": swapOwner.hex(eip55: true)
            ])
            
            let gasEstimation = try awaitPromise(suggestedGasFees())

            debug("swap order suggested medium fees: \(gasEstimation.medium)")
            debug("swap order suggested high fees: \(gasEstimation.high)")
            
            let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
            let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxPriorityFeePerGas).gwei)
            
            guard let swapOrderTx = dexContract.swapOrder(
                secretHash: secretHash,
                sellAsset: sellAsset,
                sellAmount: order.sellAmount,
                swapOwner: swapOwner
            ).createTransaction(
                nonce: nonce,
                gasPrice: nil,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxPriorityFeePerGas,
                gasLimit: EthereumQuantity(quantity: 300_000),
                from: swapOwner,
                value: quantity,
                accessList: [:],
                transactionType: .eip1559
            ) else {
                self.error("Failed to create swap transaction", ["Ethereum"])
                return reject(SwapSDKError.msg("failed to build swap order tx"))
            }
            
            let signedSwapOrderTx = try sign(transaction: swapOrderTx)
            let txId = try awaitPromise(web3.eth.publish(transaction: signedSwapOrderTx))
            
            debug("swap order tx hash: \(txId)")
            
            let topics = DexContract.OrderCreated.topics()
            
            try web3.eth.subscribeToLogs(addresses: [dexContractAddress], topics: topics) { subscription in
                guard let error = subscription.error else {
                    guard let subscriptionId = subscription.result else { return }
                    return self.subscriptionsIds.append(subscriptionId)
                }
                
                guard self.connected else { return }
                self.error("OrderCreated subscription error", [error])
            } onEvent: { log in
                if let error = log.error {
                    guard self.connected else { return }
                    self.error("order error", [error])
                } else {
                    if let topicValue = log.result,
                       let orderCreatedEvent = try? ABI.decodeLog(event: DexContract.OrderCreated, from: topicValue),
                       let _secretHash = orderCreatedEvent["secretHash"] as? Data,
                       let sellAsset = orderCreatedEvent["sellAsset"] as? EthereumAddress,
                       let sellAmount = orderCreatedEvent["sellAmount"] as? BigUInt,
                       let swapOwner = orderCreatedEvent["swapOwner"] as? EthereumAddress,
                       let swapId = orderCreatedEvent["swapId"] as? Data,
                       let swapCreation = orderCreatedEvent["swapCreation"] as? BigUInt
                    {
                        guard secretHash == _secretHash else {
                            return self.warn("received order created from differrent swap")
                        }
                        
                        self.currentSwapId = swapId
                        
                        let logEvent = [
                            "swapId": "0x\(swapId.hexString)",
                            "secretHash": "0x\(secretHash.hexString)",
                            "sellAsset": sellAsset.hex(eip55: true),
                            "sellAmount": sellAmount.description,
                            "swapCreation": swapCreation.description,
                            "swapOwner": swapOwner.hex(eip55: true)
                        ]
                        
                        let orderCreatedEvent = OrderCreatedEvent(
                            secretHash: _secretHash.hexString,
                            sellAsset: sellAsset.hex(eip55: true),
                            sellAmount: sellAmount,
                            swapOwner: swapOwner.hex(eip55: true),
                            swapId: swapId.hexString,
                            swapCreation: swapCreation
                        )
                        
                        let receipt = [
                            "blockHash": topicValue.blockHash?.hex() ?? "?",
                            "from": swapOrderTx.from?.hex(eip55: true) ?? "?",
                            "to": swapOrderTx.to?.hex(eip55: true) ?? "?",
                            "transactionHash": topicValue.transactionHash?.hex() ?? "?",
                            "status": "succeeded",
                        ]
                        
                        let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                        
                        self.info("create order tx receipt", mergedReceipt, logEvent)
                        self.emit(event: "order.created", args: [orderCreatedEvent])
                        
                        resolve(mergedReceipt)
                    } else {
                        reject(SwapSDKError.msg("Order created event has no logs"))
                    }
                }
            }
        }
    }
    
    func authorize(swapId: Data, withdrawals: [AuthorizedWithdrawal]) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let dexContract, let dexContractAddress = dexContract.address else {
                return reject(SwapSDKError.msg("Dex contract is nil"))
            }
            
            debug("authorize params", [
                "swapId": swapId,
                "withdrawals": withdrawals
            ])
            
            let swapOwner = try publicAddress()
            let nonce = try awaitPromise(web3.eth.getNonce(address: swapOwner))
            let gasEstimation = try awaitPromise(suggestedGasFees())
            
            debug("authorize suggested medium fees: \(gasEstimation.medium)")
            debug("authorize suggested hight fees: \(gasEstimation.high)")
            
            let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
            let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxPriorityFeePerGas).gwei)
            
            guard let authorizeTx = dexContract.authorize(
                swapId: swapId,
                withdrawals: withdrawals
            ).createTransaction(
                nonce: nonce,
                gasPrice: nil,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxPriorityFeePerGas,
                gasLimit: EthereumQuantity(quantity: 300_000),
                from: swapOwner,
                value: EthereumQuantity(quantity: 0),
                accessList: [:],
                transactionType: .eip1559
            ) else {
                self.error("Authorize tx failed", ["Ethereum"])
                return reject(SwapSDKError.msg("authorize tx build failed"))
            }
            
            let signedAuthorizeTx = try sign(transaction: authorizeTx)
            let txId = try awaitPromise(web3.eth.publish(transaction: signedAuthorizeTx))
            
            debug("authorize tx hash: \(txId)")
            
            let topics = DexContract.Authorized.topics()
            
            try web3.eth.subscribeToLogs(addresses: [dexContractAddress], topics: topics) { subscription in
                guard let error = subscription.error else {
                    guard let subscriptionId = subscription.result else { return }
                    return self.subscriptionsIds.append(subscriptionId)
                }
                guard self.connected else { return }
                self.error("Authorized subscription error", [error])
            } onEvent: { log in
                if let error = log.error {
                    guard self.connected else { return }
                    self.error("order error", [error])
                } else {
                    if
                        let topicValue = log.result,
                        let authorizedEvent = try? ABI.decodeLog(event: DexContract.Authorized, from: topicValue),
                        let swapId = authorizedEvent["swapId"] as? Data
                    {
                        
                        guard self.currentSwapId == swapId || self.sdk.blockchains.portal.currentSwapId == swapId else {
                            return self.warn("received lp Authorized event, current swapId not matches swapId")
                        }
                        
                        let logEvent = [
                            "swapId": "0x\(swapId.hexString)"
                        ]
                        
                        let receipt = [
                            "blockHash": topicValue.blockHash?.hex() ?? "?",
                            "from": authorizeTx.from?.hex(eip55: true) ?? "?",
                            "to": authorizeTx.to?.hex(eip55: true) ?? "?",
                            "transactionHash": topicValue.transactionHash?.hex() ?? "?",
                            "status": "succeeded"
                        ]
                        
                        let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                        self.info("authorize receip tx receipt", mergedReceipt)
                        resolve(mergedReceipt)
                    } else {
                        reject(SwapSDKError.msg("Authorize event empty logs"))
                    }
                }
            }
        }
    }
    
    func settle(invoice: Invoice, secret: Data) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let liquidityProvider else {
                return reject(SwapSDKError.msg("liquidity provider contract is not set"))
            }
            
            guard let swapIdHex = invoice["swapId"] else {
                return reject(SwapSDKError.msg("settle invoice party isn't set"))
            }
            
            let swapId = Data(hex: swapIdHex)
            let swapOwner = try publicAddress()
            
            let nonce = try awaitPromise(web3.eth.getNonce(address: swapOwner))
            let gasEstimation = try awaitPromise(suggestedGasFees())
            
            debug("settle invoice suggested medium fees: \(gasEstimation.medium)")
            debug("settle invoice suggested hight fees: \(gasEstimation.high)")
            
            let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
            let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxPriorityFeePerGas).gwei)
            
            guard let settleTx = liquidityProvider.settle(
                secret: secret,
                swapId: swapId
            ).createTransaction(
                nonce: nonce,
                gasPrice: nil,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxPriorityFeePerGas,
                gasLimit: EthereumQuantity(quantity: 300_000),
                from: swapOwner,
                value: EthereumQuantity(quantity: 0),
                accessList: [:],
                transactionType: .eip1559
            ) else {
                self.error("settle tx error", ["settle tx creation failed"])
                return reject(SwapSDKError.msg("failed to build settle invoice tx"))
            }
            
            let signedSettleTx = try sign(transaction: settleTx)
            let txId = try awaitPromise(web3.eth.publish(transaction: signedSettleTx))

            debug("settle invoice tx hash: \(txId)")
            
            let topics = LiquidityProvider.InvoiceSettled.topics()
            
            try web3.eth.subscribeToLogs(addresses: [liquidityProvider.address!], topics: topics) { subscription in
                guard let error = subscription.error else {
                    guard let subscriptionId = subscription.result else { return }
                    return self.subscriptionsIds.append(subscriptionId)
                }
                guard self.connected else { return }
                self.error("InvoiceSettled subscription error", [error])
            } onEvent: { log in
                if let error = log.error {
                    guard self.connected else { return }
                    self.error("order error", [error])
                } else {
                    if
                        let topicValue = log.result,
                        let settleEvent = try? ABI.decodeLog(event: LiquidityProvider.InvoiceSettled, from: topicValue),
                        let swapId = settleEvent["swapId"] as? Data,
                        let secret = settleEvent["secret"] as? Data,
                        let counterParty = settleEvent["counterParty"] as? EthereumAddress,
                        let sellAsset = settleEvent["sellAsset"] as? EthereumAddress,
                        let sellAmount = settleEvent["sellAmount"] as? BigUInt
                    {
                        guard self.currentSwapId == swapId || self.sdk.blockchains.portal.currentSwapId == swapId else {
                            return self.warn("received lp InvoiceSettled event, current swapId not matches swapId")
                        }
                        
                        let logEvent = [
                            "swapId": "0x\(swapId.hexString)",
                            "secret": "0x\(secret.hexString)",
                            "counterParty": "\(counterParty.hex(eip55: true))",
                            "sellAsset": "\(sellAsset.hex(eip55: true))",
                            "sellAmount": "\(sellAmount.description)"
                        ]
                        
                        let receipt = [
                            "blockHash": topicValue.blockHash?.hex() ?? "?",
                            "from": settleTx.from?.hex(eip55: true) ?? "?",
                            "to": settleTx.to?.hex(eip55: true) ?? "?",
                            "transactionHash": topicValue.transactionHash?.hex() ?? "?",
                            "status": "succeeded",
                        ]
                        
                        let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                        self.info("settle event tx receipt", mergedReceipt, logEvent)
                        
                        if let mainId = invoice["mainId"] {
                            self.emit(event: "invoice.settled", args: [swapIdHex, mainId])
                        } else {
                            self.emit(event: "invoice.settled", args: [swapIdHex])
                        }
                        
                        resolve(mergedReceipt)
                    } else {
                        reject(SwapSDKError.msg("Settle event empty logs"))
                    }
                }
            }
        }
    }
    
    func feePercentage() -> Promise<BigUInt> {
        Promise { [unowned self] resolve, reject in
            guard let dexContract else {
                return reject(SwapSDKError.msg("dex contract is missing"))
            }
            
            dexContract.feePercentage().call { response, error in
                if let response {
                    guard let fee = response[""] as? BigUInt else {
                        return reject(SwapSDKError.msg("Failed to parse pools array"))
                    }
                    
                    resolve(fee)
                } else if let error {
                    reject(error)
                } else {
                    reject(SwapSDKError.msg("fee percentage unexpected response"))
                }
            }
        }
    }
    
    func publicAddress() throws -> EthereumAddress {
        let key = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
        let hexString = key.address.hex(eip55: false)
        
        guard
            let publicAddress = EthereumAddress(hexString: hexString)
        else {
            throw SwapSDKError.msg("cannot unwrap eth pub address")
        }
        
        return publicAddress
    }
    
    func create(invoice: Invoice) -> Promise<Response> {
        Promise { resolve, reject in
            
        }
    }
}

extension Ethereum {
    private func suggestedGasFees() -> Promise<GasEstimateResponse> {
        Promise { resolve, reject in
            let gasFeeUrlPath = "https://gas.api.infura.io/v3/7bffa4b191da4e9682d4351178c4736e/networks/11155111/suggestedGasFees"
            let gasFeeUrl = URL(string: gasFeeUrlPath)!
            var request = URLRequest(url: gasFeeUrl)
            
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard error == nil, let data, let fees = try? JSONDecoder().decode(GasEstimateResponse.self, from: data) else {
                    return reject(SwapSDKError.msg("fetching infura gas fees failed"))
                }
                resolve(fees)
            }
            .resume()
        }
    }
        
    private func sign(transaction: EthereumTransaction) throws -> EthereumSignedTransaction {
        let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
        return try transaction.sign(with: privKey, chainId: EthereumQuantity.string(props.chainId))
    }
}
