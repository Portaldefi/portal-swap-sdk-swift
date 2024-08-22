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
    private var swapContract: DynamicContract!
    private var dexContract: DynamicContract!
    
    private var subscriptionsIDS = [String]()
    private let subscriptionAccessQueue = DispatchQueue(label: "swap.sdk.subscriptionAccessQueue")
    
    // Sdk seems unused
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Ethereum) {
        self.sdk = sdk
        self.props = props
        super.init(id: "Ethereum")
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                websocketProvider = try Web3WebSocketProvider(wsUrl: props.url)
                web3 = Web3(provider: websocketProvider)
                
                //dex contract
                guard
                    let contract = props.contracts["Dex"] as? [String: Any],
                    let abiArray = contract["abi"] as? [[String: Any]],
                    let contractAddressHex = contract["address"] as? String
                else {
                    return reject(SwapSDKError.msg("Ethereum cannot prepare contract"))
                }
                
                let dexContractAddresisEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
                
                let dexContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: dexContractAddresisEipp55)
                let dexContractData = try JSONSerialization.data(withJSONObject: abiArray, options: [])
                
                dexContract = try web3.eth.Contract(json: dexContractData, abiKey: nil, address: dexContractAddress)
                
                //dex contract subscriptions
                for (index, event) in dexContract.events.enumerated() {
                    print(event.name)
                    
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
                    case "SwapIntended":
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("SwapIntended self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                debug("\(sdk.userId) OrderCreated subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { [unowned self] (response: Web3Response<OrderCreatedEvent>) in
                            switch response.status {
                            case .success(let event):
                                print("OrderCreatedEvent: \(event)")

                                let status = "trader.order.created"
                                
                                self.info(status, [event])
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
                
                for method in dexContract.methods {
                    print(method)
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
        
    func swapIntent(_ intent: SwapIntent) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            debug("Swap Secret Hash: \(intent.secretHash.toHexString())")
            
            guard let sellAsset = EthereumAddress(hexString: intent.sellAddress) else {
                return reject(SwapSDKError.msg("Cannot unwrap sell asset address"))
            }
            
            guard let buyAsset = EthereumAddress(hexString: intent.buyAddress) else {
                return reject(SwapSDKError.msg("Cannot unwrap buy asset address"))
            }
                        
            let secretHash = intent.secretHash
            let traderBuyId = BigUInt(intent.traderBuyId.makeBytes())
            let sellAmount = BigUInt(intent.sellAmount.makeBytes())
            let buyAmount = BigUInt(intent.buyAmount.makeBytes())
            let buyAmountSlippage = BigUInt(intent.buyAmountSlippage.makeBytes())
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            
            guard let swapOwner = EthereumAddress(hexString: privKey.address.hex(eip55: false)) else {
                return reject(SwapSDKError.msg("Cannot unwrap buy asset address"))
            }
                        
            let params = SolidityTuple([
                SolidityWrappedValue(value: secretHash, type: .bytes(length: 32)),
                SolidityWrappedValue(value: traderBuyId, type: .uint256),
                SolidityWrappedValue(value: sellAsset, type: .address),
                SolidityWrappedValue(value: sellAmount, type: .uint256),
                SolidityWrappedValue(value: buyAsset, type: .address),
                SolidityWrappedValue(value: buyAmount, type: .uint256),
                SolidityWrappedValue(value: buyAmountSlippage, type: .uint256),
                SolidityWrappedValue(value: swapOwner, type: .address)
            ])
                                    
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    debug("Eth create invoice nonce: \(nonce.quantity)")
                    
                    let quantity = EthereumQuantity(quantity: sellAmount)
                    
                    guard let tx = self.dexContract["swapIntent"]?(params).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 300_000),
                        from: privKey.address,
                        value: quantity,
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        self.debug("SWAP INTENT TX ERROR")
                        return reject(SwapSDKError.msg("Ethereum failed to create swap intent transaction"))
                    }
                    
                    do {
                        let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                        
                        try self.web3.eth.sendRawTransaction(transaction: signedTx) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("web3.eth.sendRawTransaction self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let data):
                                self.debug("swap order TH HASH: \(data.hex())")
                                
                                Thread.sleep(forTimeInterval: 1)
                                
                                self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                    guard let self = self else {
                                        return reject(SwapSDKError.msg("getTransactionReceipt self is nil"))
                                    }
                                    
                                    switch response.status {
                                    case .success(let txReceipt):
                                        if let txReceipt {
                                            print("logs: \(txReceipt.logs)")
                                            print("status: \(txReceipt.status)")
                                            
                                            let receipt = [
                                                "blockHash": txReceipt.blockHash.hex(),
                                                "from": privKey.address.hex(eip55: false),
                                                "to": self.dexContract.address!.hex(eip55: false),
                                                "transactionHash": txReceipt.transactionHash.hex()
                                            ]
                                            
                                            self.info("swap order reciep", receipt, self as Any)
                                            resolve(receipt)
                                        }
                                    case .failure(let error):
                                        print("SWAP SDK ETH Fetching receip error: \(error)")
                                        return reject(error)
                                    }
                                }
                            case .failure(let error):
                                self.debug("SENDING TX ERROR: \(error)")
                                reject(error)
                            }
                        }
                    } catch {
                        self.debug("SENDING TX ERROR: \(error)")
                        reject(error)
                    }
                case .failure(let error):
                    self.debug("Getting nonce ERROR: \(error)")
                    break
                }
            })
            
        }
    }
    
    func createInvoice(party: Party) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            guard let swap = party.swap else {
                return reject(SwapSDKError.msg("There is no swap or secret hash"))
            }
            
            debug("Creating invoice for party with id: \(party.id)")
                        
            guard let id = Utils.hexToData(swap.secretHash) else {
                return reject(SwapSDKError.msg("Cannot unwrap secret hash"))
            }
            
            guard let swap = Utils.hexToData(swap.swapId) else {
                return reject(SwapSDKError.msg("Cannot unwrap swap id"))
            }
            
            let asset = EthereumAddress(hexString: "0x0000000000000000000000000000000000000000")!
            let quantity = BigInt(party.quantity)
            
            let params = SolidityTuple([
                SolidityWrappedValue(value: id, type: .bytes(length: 32)),
                SolidityWrappedValue(value: swap, type: .bytes(length: 32)),
                SolidityWrappedValue(value: asset, type: .address),
                SolidityWrappedValue(value: quantity, type: .uint256)
            ])
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    debug("Eth create invoice nonce: \(nonce.quantity)")
                    
                    guard let tx = self.swapContract["createInvoice"]?(params).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 200_000),
                        from: privKey.address,
                        value: 0,
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        self.debug("CREATING INVOICE TX ERROR")
                        return reject(SwapSDKError.msg("Ethereum failed to create transaction"))
                    }
                    
                    do {
                        let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                        
                        try self.web3.eth.sendRawTransaction(transaction: signedTx) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("web3.eth.sendRawTransaction self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let data):
                                self.debug("Create invoice TH HASH: \(data.hex())")
                                
                                let receipt = [
                                    "blockHash": "recipe.blockHash.hex()",
                                    "from": privKey.address.hex(eip55: false),
                                    "to": self.swapContract.address!.hex(eip55: false),
                                    "transactionHash": data.hex()
                                ]
                                
                                self.info("create invoice", "partyId: \(party.id)", receipt)
                                resolve(receipt)
                            case .failure(let error):
                                self.debug("SENDING TX ERROR: \(error)")
                                reject(error)
                            }
                        }
                    } catch {
                        self.debug("SENDING TX ERROR: \(error)")
                        reject(error)
                    }
                case .failure(let error):
                    self.debug("Getting nonce ERROR: \(error)")
                    break
                }
            })
        }
    }
    
    func payInvoice(party: Party) -> Promise<[String: Any]> {
        Promise { [unowned self] resolve, reject in
            guard let swap = party.swap else {
                return reject(SwapSDKError.msg("There is no swap or secret hash"))
            }
            
            let secretHash = swap.secretHash
            
            guard let id = Utils.hexToData(secretHash) else {
                return reject(SwapSDKError.msg("Cannot unwrap secret hash"))
            }
            
            guard let swap = Utils.hexToData(swap.swapId) else {
                return reject(SwapSDKError.msg("Cannot unwrap swap id"))
            }
            
            let asset = EthereumAddress(hexString: "0x0000000000000000000000000000000000000000")!
            let quantity = BigUInt(party.quantity)
            
            let params = SolidityTuple([
                SolidityWrappedValue(value: id, type: .bytes(length: 32)),
                SolidityWrappedValue(value: swap, type: .bytes(length: 32)),
                SolidityWrappedValue(value: asset, type: .address),
                SolidityWrappedValue(value: quantity, type: .uint256)
            ])
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    debug("Eth pay invoice nonce: \(nonce.quantity)")
                    
                    guard let tx = self.swapContract["payInvoice"]?(params).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 200_000),
                        from: privKey.address,
                        value: EthereumQuantity(quantity: quantity),
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        self.debug("PAYING INVOICE TX ERROR")
                        return reject(SwapSDKError.msg("Ethereum failed to create transaction"))
                    }
                    
                    do {
                        let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                        
                        try self.web3.eth.sendRawTransaction(transaction: signedTx) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("web3.eth.sendRawTransaction self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let data):
                                self.debug("Pay invoice TH HASH: \(data.hex())")
                                
                                let receipt = [
                                    "blockHash": "recipe.blockHash.hex()",
                                    "from": privKey.address.hex(eip55: false),
                                    "to": self.swapContract.address!.hex(eip55: false),
                                    "transactionHash": data.hex()
                                ]
                                
                                self.info("pay invoice", "partyId: \(party.id)", receipt)
                                resolve(receipt)
                            case .failure(let error):
                                self.debug("SENDING TX ERROR: \(error)")
                                reject(error)
                            }
                        }
                    } catch {
                        self.debug("SENDING TX ERROR: \(error)")
                        reject(error)
                    }
                case .failure(let error):
                    self.debug("Getting nonce ERROR: \(error)")
                    break
                }
            })
        }
    }
    
    func settleInvoice(party: Party, secret: Data) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            guard let swap = party.swap else {
                return reject(SwapSDKError.msg("There is no swap or secret hash"))
            }
            
            guard let swap = Utils.hexToData(swap.swapId) else {
                return reject(SwapSDKError.msg("Cannot unwrap swap id"))
            }
            
            let params = SolidityTuple([
                SolidityWrappedValue(value: secret, type: .bytes(length: 32)),
                SolidityWrappedValue(value: swap, type: .bytes(length: 32))
            ])
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    debug("Eth settle invoice nonce: \(nonce.quantity)")
                    
                    guard let tx = self.swapContract["settleInvoice"]?(params).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 200_000),
                        from: privKey.address,
                        value: 0,
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        self.debug("CREATING TX ERROR")
                        return reject(SwapSDKError.msg("Ethereum failed to create transaction"))
                    }
                    
                    do {
                        let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                        
                        try self.web3.eth.sendRawTransaction(transaction: signedTx) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("web3.eth.sendRawTransaction self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let data):
                                self.debug("Settle invoice TH HASH: \(data.hex())")
                                
                                let receipt = [
                                    "blockHash": "recipe.blockHash.hex()",
                                    "from": privKey.address.hex(eip55: false),
                                    "to": self.swapContract.address!.hex(eip55: false),
                                    "transactionHash": data.hex()
                                ]
                                
                                self.info("settle invoice", "partyId: \(party.id)", receipt)
                                resolve(receipt)
                            case .failure(let error):
                                self.debug("SENDING TX ERROR: \(error)")
                                reject(error)
                            }
                        }
                    } catch {
                        self.debug("SENDING TX ERROR: \(error)")
                        reject(error)
                    }
                case .failure(let error):
                    self.debug("Getting nonce ERROR: \(error)")
                    break
                }
            })
        }
    }
}
