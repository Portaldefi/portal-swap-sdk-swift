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
    
    private var subscriptionsIDS = [String]()
    private let subscriptionAccessQueue = DispatchQueue(label: "swap.sdk.subscriptionAccessQueue")
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Ethereum) {
        self.sdk = sdk
        self.props = props
        super.init(id: "ethereum")
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                websocketProvider = try Web3WebSocketProvider(wsUrl: props.url)
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
                
                guard let dexContract else {
                    return reject(SwapSDKError.msg("Ethereum cannot prepare contract"))
                }
                
                //dex contract subscriptions
                for (index, event) in dexContract.events.enumerated() {
                    let signatureHex = "0x\(Utils.keccak256Hash(of: event.signature))"
                    let addresses = [dexContractAddress]
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
                    case DexContract.OrderCreated.name:
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("OrderCreated event self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                self.error("subscription failed", [
                                    "userId": sdk.userId,
                                    "event": event.name,
                                    "error": error
                                ])
                            }
                        } onEvent: { [unowned self] (response: Web3Response<OrderCreatedEvent>) in
                            switch response.status {
                            case .success(let event):
                                print("\(DexContract.OrderCreated.name): \(event)")

                                let status = "order.created"
                                
                                self.info("swap status updated", [
                                    "status": "order.created",
                                    "event": event
                                ])
                                self.emit(event: status, args: [event])
                            case .failure(let error):
                                debug("\(sdk.userId) SwapIntended subscription event fail error: \(error)")
                                self.error("error", [error, self])
                            }
                        }
                    default:
                        continue
                    }
                }
                
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
                
                guard let liquidityProvider else {
                    return reject(SwapSDKError.msg("liquidityProvider cannot prepare contract"))
                }
                
                //liquidityProvider contract subscriptions
                for (index, event) in liquidityProvider.events.enumerated() {
                    let signatureHex = "0x\(Utils.keccak256Hash(of: event.signature))"
                    
                    debug("event signature", [
                        "event": event.name,
                        "signature": signatureHex
                    ])
                    
                    let addresses = [lpContractAddress]
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
                    case LiquidityProvider.InvoiceCreated.name:
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("ethereum is missing"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                self.error("subscription failed", [
                                    "userId": sdk.userId,
                                    "event": event.name,
                                    "error": error
                                ])
                            }
                        } onEvent: { [unowned self] (response: Web3Response<InvoiceCreatedEvent>) in
                            switch response.status {
                            case .success(let event):
                                let status = "lp.invoice.created"
                                
                                self.info("swap status updated", [
                                    "status": status,
                                    "event": event
                                ])
                                self.emit(event: status, args: [event])
                            case .failure(let error):
                                debug("\(sdk.userId) SwapIntended subscription event fail error: \(error)")
                                self.error("error", [error, self])
                            }
                        }
                    case LiquidityProvider.InvoiceSettled.name:
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("ethereum is missing"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                self.error("subscription failed", [
                                    "userId": sdk.userId,
                                    "event": event.name,
                                    "error": error
                                ])
                            }
                        } onEvent: { [unowned self] (response: Web3Response<InvoiceSettledEvent>) in
                            switch response.status {
                            case .success(let event):
                                let status = "invoice.settled"
                                
                                self.info("swap status updated", [
                                    "status": status,
                                    "event": event
                                ])
                                self.emit(event: status, args: [event])
                            case .failure(let error):
                                debug("InvoiceSettledEvent subscription event fail error: \(error)")
                                self.error("error", [error, self])
                            }
                        }
                    default:
                        continue
                    }
                }
                
                self.info("connect")
                self.emit(event: "connect", args: [self])
                resolve(())
            } catch {
                self.error("connect", [error, self])
                reject(error)
            }
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            for subscriptionsId in subscriptionsIDS {
                websocketProvider.unsubscribe(subscriptionId: subscriptionsId, completion: { _ in ()})
            }
            subscriptionsIDS.removeAll()
            
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
            guard let dexContract else {
                return reject(SwapSDKError.msg("Dex contract is nil"))
            }
            
            guard let sellAsset = EthereumAddress(hexString: order.sellAddress) else {
                return reject(SwapSDKError.msg("Cannot unwrap sell asset address"))
            }
            
            let swapOwner = try publicAddress()
                                                            
            web3.eth.getTransactionCount(address: swapOwner, block: .latest, response: { [weak self] nonceResponse in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch nonceResponse.status {
                case .success(let nonce):
                    print("eth transaction nonce: \(nonce.quantity)")
                    let quantity = EthereumQuantity(quantity: order.sellAmount)
                    
                    debug("swap order params", [
                        "secretHash": "0x\(secretHash.hexString)",
                        "sellAsset": sellAsset.hex(eip55: true),
                        "sellAmount": order.sellAmount.description,
                        "swapOwner": swapOwner.hex(eip55: true)
                    ])
                    
                    suggestedGasFees { [weak self] gasEstimation in
                        guard let self else {
                            return reject(SwapSDKError.msg("gas fees self is nil"))
                        }
                        guard let gasEstimation else {
                            return reject(SwapSDKError.msg("failed update gas fees"))
                        }
                        
                        print("settle invoice suggested medium fees: \(gasEstimation.medium)")
                        print("settle invoice suggested hight fees: \(gasEstimation.high)")
                        
                        let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
                        let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.high.suggestedMaxPriorityFeePerGas).gwei)
                        
                        guard let swapOrderTx = dexContract.swapOrder(
                            secretHash: secretHash,
                            sellAsset: sellAsset,
                            sellAmount: order.sellAmount,
                            swapOwner: swapOwner
                        )
                        .createTransaction(
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
                            self.error("Create tx", [
                                "secretHash": "0x\(secretHash.hexString)",
                                "sellAsset": sellAsset.hex(eip55: true),
                                "sellAmount": order.sellAmount.description,
                                "swapOwner": swapOwner.hex(eip55: true)
                            ])
                            return reject(SwapSDKError.msg("failed to build swap order tx"))
                        }
                        
                        do {
                            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(self.props.privKey)")
                            let signedSwapOrderTx = try swapOrderTx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                            
                            try self.web3.eth.sendRawTransaction(transaction: signedSwapOrderTx) { [weak self] response in
                                guard let self = self else {
                                    return reject(SwapSDKError.msg("ethereum is missing"))
                                }
                                
                                switch response.status {
                                case .success(let data):
                                    self.debug("swap order tx hash: \(data.hex())")
                                    
                                    Thread.sleep(forTimeInterval: 3)
                                    
                                    self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                        guard let self = self else {
                                            return reject(SwapSDKError.msg("getTransactionReceipt self is nil"))
                                        }
                                        
                                        switch response.status {
                                        case .success(let txReceipt):
                                            if let txReceipt {
                                                var logEvent: [String: String]?
                                                
                                                for log in txReceipt.logs {
                                                    if let orderCreatedEvent = try? ABI.decodeLog(event: DexContract.OrderCreated, from: log),
                                                       let secretHash = orderCreatedEvent["secretHash"] as? Data,
                                                       let sellAsset = orderCreatedEvent["sellAsset"] as? EthereumAddress,
                                                       let sellAmount = orderCreatedEvent["sellAmount"] as? BigUInt,
                                                       let swapOwner = orderCreatedEvent["swapOwner"] as? EthereumAddress,
                                                       let swapId = orderCreatedEvent["swapId"] as? Data,
                                                       let swapCreation = orderCreatedEvent["swapCreation"] as? BigUInt
                                                    {
                                                        logEvent = [
                                                            "swapId": "0x\(swapId.hexString)",
                                                            "secretHash": "0x\(secretHash.hexString)",
                                                            "sellAsset": sellAsset.hex(eip55: true),
                                                            "sellAmount": sellAmount.description,
                                                            "swapCreation": swapCreation.description,
                                                            "swapOwner": swapOwner.hex(eip55: true)
                                                        ]
                                                        
                                                        break
                                                    }
                                                    
                                                }
                                                
                                                let status = txReceipt.status?.quantity == 1 ? "succeded": "failed"
                                                
                                                let receipt = [
                                                    "blockHash": txReceipt.blockHash.hex(),
                                                    "from": swapOrderTx.from?.hex(eip55: true) ?? "?",
                                                    "to": swapOrderTx.to?.hex(eip55: true) ?? "?",
                                                    "transactionHash": txReceipt.transactionHash.hex(),
                                                    "status": status,
                                                    "logs": "\(txReceipt.logs.count)"
                                                ]
                                                
                                                if let logEvent {
                                                    let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                                                    self.info("create swap tx receipt", mergedReceipt)
                                                    resolve(mergedReceipt)
                                                } else {
                                                    self.info("create swap receipt", receipt)
                                                    resolve(receipt)
                                                }
                                            }
                                        case .failure(let error):
                                            self.warn("fetching receipt error", error)
                                        }
                                    }
                                case .failure(let error):
                                    reject(error)
                                }
                            }
                        } catch {
                            reject(error)
                        }
                        
                    }
                case .failure(let error):
                    reject(error)
                }
            })
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
    
    func authorize(swapId: Data, withdrawals: [AuthorizedWithdrawal]) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let dexContract else {
                return reject(SwapSDKError.msg("dex contract is missing"))
            }
            
            let swapOwner = try publicAddress()
            
            web3.eth.getTransactionCount(address: swapOwner, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                }
                
                debug("authorize params", [
                    "swapId": swapId,
                    "withdrawals": withdrawals
                ])
                
                switch response.status {
                case .success(let nonce):
                    print("eth transaction nonce: \(nonce.quantity)")

                    suggestedGasFees { [weak self] gasEstimation in
                        guard let self else {
                            return reject(SwapSDKError.msg("gas fees self is nil"))
                        }
                        guard let gasEstimation else {
                            return reject(SwapSDKError.msg("failed update gas fees"))
                        }
                        
                        print("settle invoice suggested medium fees: \(gasEstimation.medium)")
                        print("settle invoice suggested hight fees: \(gasEstimation.high)")
                        
                        let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
                        let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.high.suggestedMaxPriorityFeePerGas).gwei)
                        
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
                            self.error("authorize tx", [
                                "swapId": swapId,
                                "withdrawals": withdrawals
                            ])
                            return reject(SwapSDKError.msg("authorize tx build failed"))
                        }
                        
                        do {
                            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(self.props.privKey)")
                            let signedAuthorizeTx = try authorizeTx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                            
                            try self.web3.eth.sendRawTransaction(transaction: signedAuthorizeTx) { [weak self] response in
                                guard let self = self else {
                                    return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                                }
                                
                                switch response.status {
                                case .success(let data):
                                    self.debug("authorize tx hash: \(data.hex())")
                                    
                                    Thread.sleep(forTimeInterval: 3)
                                    
                                    self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                        guard let self = self else {
                                            return reject(SwapSDKError.msg("notary blockchain interface is missing"))
                                        }
                                        
                                        switch response.status {
                                        case .success(let txReceipt):
                                            if let txReceipt {
                                                var logEvent: [String: String]?
                                                
                                                for log in txReceipt.logs {
                                                    if let swapCreatedEvent = try? ABI.decodeLog(event: ADMMContract.SwapCreated, from: log),
                                                       let swap = swapCreatedEvent["swap"] as? [Any],
                                                       let id = swap[0] as? Data,
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
                                                        logEvent = [
                                                            "id": "0x\(id.hexString)",
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
                                                        
                                                        break
                                                    }
                                                    
                                                }
                                                
                                                let status = txReceipt.status?.quantity == 1 ? "succeded": "failed"
                                                
                                                let receipt = [
                                                    "blockHash": txReceipt.blockHash.hex(),
                                                    "from": authorizeTx.from?.hex(eip55: true) ?? "?",
                                                    "to": authorizeTx.to?.hex(eip55: true) ?? "?",
                                                    "transactionHash": txReceipt.transactionHash.hex(),
                                                    "status": status,
                                                    "logs": "\(txReceipt.logs.count)"
                                                ]
                                                
                                                if let logEvent {
                                                    let mergedReceipt = receipt.merging(logEvent) { (current, _) in current }
                                                    self.info("create swap receipt", mergedReceipt)
                                                    resolve(mergedReceipt)
                                                } else {
                                                    self.info("create swap receipt", receipt)
                                                    resolve(receipt)
                                                }
                                            }
                                        case .failure(let error):
                                            warn("authorize receip", ["error": error])
                                            
                                            let receipt: [String: String] = [
                                                "txId": data.hex(),
                                                "from": authorizeTx.from?.hex(eip55: true) ?? "?",
                                                "to": authorizeTx.to?.hex(eip55: true) ?? "?",
                                                "status": "unknown"
                                            ]
                                            
                                            return resolve(receipt)
                                        }
                                    }
                                case .failure(let error):
                                    self.error("authorize swap tx error", [error])
                                    reject(error)
                                }
                            }
                        } catch {
                            self.error("authorize tx", [error])
                            reject(error)
                        }
                    }
                case .failure(let error):
                    self.error("Nonce", [error])
                    break
                }
            })
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
    
    func settle(invoice: Invoice, secret: Data) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let liquidityProvider else {
                return reject(SwapSDKError.msg("liquidity provider contract is not set"))
            }
            
            guard let swapIdHex = invoice["swapId"] else {
                return reject(SwapSDKError.msg("settle invoice party isn't set"))
            }
            
            let swapId = Data(hex: swapIdHex)
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
                        
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    print("eth transaction nonce: \(nonce.quantity)")

                    suggestedGasFees { [weak self] gasEstimation in
                        guard let self else {
                            return reject(SwapSDKError.msg("gas fees self is nil"))
                        }
                        guard let gasEstimation else {
                            return reject(SwapSDKError.msg("failed update gas fees"))
                        }
                        
                        print("settle invoice suggested medium fees: \(gasEstimation.medium)")
                        print("settle invoice suggested hight fees: \(gasEstimation.high)")
                        
                        let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
                        let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.high.suggestedMaxPriorityFeePerGas).gwei)
                        
                        guard let settleTx = liquidityProvider.settle(
                            secret: secret,
                            swapId: swapId
                        ).createTransaction(
                            nonce: nonce,
                            gasPrice: nil,
                            maxFeePerGas: maxFeePerGas,
                            maxPriorityFeePerGas: maxPriorityFeePerGas,
                            gasLimit: EthereumQuantity(quantity: 300_000),
                            from: privKey.address,
                            value: EthereumQuantity(quantity: 0),
                            accessList: [:],
                            transactionType: .eip1559
                        ) else {
                            self.error("settle tx error")
                            return reject(SwapSDKError.msg("failed to build settle invoice tx"))
                        }
                        
                        do {
                            let signedSettleTx = try settleTx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                            
                            try self.web3.eth.sendRawTransaction(transaction: signedSettleTx) { [weak self] response in
                                guard let self = self else {
                                    return reject(SwapSDKError.msg("ethereum is missing"))
                                }
                                
                                switch response.status {
                                case .success(let data):
                                    self.debug("settle invoice tx hash: \(data.hex())")
                                    
                                    Thread.sleep(forTimeInterval: 5)
                                    
                                    self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                        guard let self = self else {
                                            return reject(SwapSDKError.msg("getTransactionReceipt self is nil"))
                                        }
                                        
                                        switch response.status {
                                        case .success(let txReceipt):
                                            if let txReceipt {
                                                var logEvent: [String: String]?
                                                
    //                                            for log in txReceipt.logs {
    //                                                if let orderCreatedEvent = try? ABI.decodeLog(event: LiquidityProvider.InvoiceSettled, from: log),
    //                                                   let secretHash = orderCreatedEvent["secretHash"] as? Data,
    //                                                   let sellAsset = orderCreatedEvent["sellAsset"] as? EthereumAddress,
    //                                                   let sellAmount = orderCreatedEvent["sellAmount"] as? BigUInt,
    //                                                   let swapOwner = orderCreatedEvent["swapOwner"] as? EthereumAddress,
    //                                                   let swapId = orderCreatedEvent["swapId"] as? Data,
    //                                                   let swapCreation = orderCreatedEvent["swapCreation"] as? BigUInt
    //                                                {
    //                                                    logEvent = [
    //                                                        "swapId": "0x\(swapId.hexString)",
    //                                                        "secretHash": "0x\(secretHash.hexString)",
    //                                                        "sellAsset": sellAsset.hex(eip55: true),
    //                                                        "sellAmount": sellAmount.description,
    //                                                        "swapCreation": swapCreation.description,
    //                                                        "swapOwner": swapOwner.hex(eip55: true)
    //                                                    ]
    //
    //                                                    break
    //                                                }
    //
    //                                            }
                                                
                                                let status = txReceipt.status?.quantity == 1 ? "succeded": "failed"
                                                
                                                let receipt = [
                                                    "blockHash": txReceipt.blockHash.hex(),
                                                    "from": privKey.address.hex(eip55: false),
                                                    "to": signedSettleTx.to!.hex(eip55: true),
                                                    "transactionHash": txReceipt.transactionHash.hex(),
                                                    "status": status,
                                                    "logs": "\(txReceipt.logs.count)"
                                                ]
                                                
                                                if status == "succeded" {
                                                    if let mainId = invoice["mainId"] {
                                                        self.emit(event: "invoice.settled", args: [swapIdHex, mainId])
                                                    } else {
                                                        self.emit(event: "invoice.settled", args: [swapIdHex])
                                                    }
                                                }
                                                
                                                self.info("settle invoice receipt", receipt)
                                                resolve(receipt)
                                            }
                                        case .failure(let error):
    //                                        print("SWAP SDK ETH Fetching receip error: \(error)")
    //                                        return reject(error)
                                            if let mainId = invoice["mainId"] {
                                                self.emit(event: "invoice.settled", args: [swapIdHex, mainId])
                                            } else {
                                                self.emit(event: "invoice.settled", args: [swapIdHex])
                                            }
                                        }
                                    }
                                case .failure(let error):
                                    self.error("Settle tx: \(error)")
                                    reject(error)
                                }
                            }
                        } catch {
                            self.error("Settle tx: \(error)")
                            reject(error)
                        }
                        
                    }
                case .failure(let error):
                    self.debug("Getting nonce ERROR: \(error)")
                    break
                }
            })
        }
    }
    
    private func suggestedGasFees(_ completion: @escaping (GasEstimateResponse?) -> Void) {
        let gasFeeUrlPath = "https://gas.api.infura.io/v3/7bffa4b191da4e9682d4351178c4736e/networks/11155111/suggestedGasFees"
        let gasFeeUrl = URL(string: gasFeeUrlPath)!
        var request = URLRequest(url: gasFeeUrl)
        
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil, let data else { return completion(nil) }
            completion(try? JSONDecoder().decode(GasEstimateResponse.self, from: data))
        }
        
        task.resume()
    }
}
