import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Ethereum: BaseClass, IBlockchain {
    private let props: SwapSdkConfig.Blockchains.Ethereum
    
    private let userID: String
    private var web3: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    private var contract: DynamicContract!
    
    private var subscriptionsIDS = [String]()
    private let subscriptionAccessQueue = DispatchQueue(label: "swap.sdk.subscriptionAccessQueue")
    
    // Sdk seems unused
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Ethereum) {
        self.props = props
        self.userID = sdk.userId
        super.init(id: "Ethereum")
    }
        
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                websocketProvider = try Web3WebSocketProvider(wsUrl: props.url)
                web3 = Web3(provider: websocketProvider)
                
                guard 
                    let swapContract = props.contracts["Swap"] as? [String: Any],
                    let abiArray = swapContract["abi"] as? [[String: Any]],
                    let contractAddressHex = swapContract["address"] as? String
                else {
                    return reject(SwapSDKError.msg("Ethereum cannot prepare contract"))
                }
                
                let isEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
                
                let contractAddress = try EthereumAddress(hex: contractAddressHex, eip55: isEipp55)
                let contractData = try JSONSerialization.data(withJSONObject: abiArray, options: [])
                
                self.contract = try web3.eth.Contract(json: contractData, abiKey: nil, address: contractAddress)
                
                for (index, event) in contract.events.enumerated() {
                    let signatureHex = "0x\(Utils.keccak256Hash(of: event.signature))"
                    let addresses = [contractAddress]
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
                    case "InvoiceCreated":
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("InvoiceCreated self is nil"))
                            }
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                debug("\(userID) InvoiceCreated subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { [weak self] (response: Web3Response<InvoiceCreatedEvent>) in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("InvoiceCreatedEvent self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let invoiceCreatedEvent):
                                debug("\(userID) received contract event: InvoiceCreatedEvent")
                                
                                guard invoiceCreatedEvent.address == contract.address!.hex(eip55: isEipp55) else {
                                    let errorMsg = "got event from \(invoiceCreatedEvent.address), expected: \(contract.address!.hex(eip55: isEipp55))"
                                    self.error("invoice.event", [errorMsg, self])
                                    self.emit(event: "error", args: [errorMsg])
                                    return
                                }
                                
                                guard invoiceCreatedEvent.eventSignature == signatureHex else {
                                    let errorMsg = "Event signature not matched. received \(invoiceCreatedEvent.eventSignature), expected: \(signatureHex)"
                                    self.error("invoice.event", [errorMsg, self])
                                    self.emit(event: "error", args: [errorMsg])
                                    return
                                }
                                
                                guard !invoiceCreatedEvent.removed else {
                                    self.error("invoice.event", ["Invoice event were removed", self])
                                    self.emit(event: "error", args: ["Invoice event were removed"])
                                    return
                                }
                                
                                let invoice: [String: Any] = [
                                    "id": invoiceCreatedEvent.id,
                                    "swap": ["id": invoiceCreatedEvent.swap],
                                    "payee": invoiceCreatedEvent.payee,
                                    "asset": invoiceCreatedEvent.asset,
                                    "quantity": invoiceCreatedEvent.quantity
                                ]
                                
                                self.info("invoice.created", invoice)
                                self.emit(event: "invoice.created", args: [invoice])
                            case .failure(let error):
                                self.error("error", [error, self])
                                self.emit(event: "error", args: [error])
                            }
                        }
                    case "InvoicePaid":
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("InvoicePaid self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                debug("\(userID) InvoicePaid subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { [weak self] (response: Web3Response<InvoicePaidEvent>) in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("InvoicePaidEvent self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let invoicePayedEvent):
                                debug("\(userID) received contract event: InvoicePaidEvent")
                                
                                guard invoicePayedEvent.address == contract.address!.hex(eip55: isEipp55) else {
                                    let errorMsg = "got event from \(invoicePayedEvent.address), expected: \(contract.address!.hex(eip55: isEipp55))"
                                    self.error("invoice.event", [errorMsg, self])
                                    self.emit(event: "error", args: [errorMsg])
                                    return
                                }
                                
                                guard invoicePayedEvent.eventSignature == signatureHex else {
                                    let errorMsg = "Event signature not matched. received \(invoicePayedEvent.eventSignature), expected: \(signatureHex)"
                                    self.error("invoice.event", [errorMsg, self])
                                    self.emit(event: "error", args: [errorMsg])
                                    return
                                }
                                
                                guard !invoicePayedEvent.removed else {
                                    self.error("invoice.event", ["Invoice event were removed", self])
                                    self.emit(event: "error", args: ["Invoice event were removed"])
                                    return
                                }
                                
                                let invoice: [String: Any] = [
                                    "id": invoicePayedEvent.id,
                                    "swap": ["id": invoicePayedEvent.swap],
                                    "payer": invoicePayedEvent.payer,
                                    "asset": invoicePayedEvent.asset,
                                    "quantity": invoicePayedEvent.quantity
                                ]
                                
                                self.info("invoice.paid", invoice)
                                self.emit(event: "invoice.paid", args: [invoice])
                            case .failure(let error):
                                self.error("error", [error, self])
                            }
                        }
                    case "InvoiceSettled":
                        websocketProvider.subscribe(request: request) { [weak self] response in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("InvoiceSettled self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let subscriptionID):
                                self.subscriptionAccessQueue.async {
                                    self.subscriptionsIDS.append(subscriptionID)
                                }
                            case .failure(let error):
                                debug("\(userID) InvoiceSettled subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { [weak self] (response: Web3Response<InvoiceSettledEvent>) in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("InvoiceSettledEvent self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let invoiceSettledEvent):
                                debug("\(userID) Received contract event: InvoiceSettledEvent")
                                
                                guard invoiceSettledEvent.address == contract.address!.hex(eip55: isEipp55) else {
                                    let errorMsg = "got event from \(invoiceSettledEvent.address), expected: \(contract.address!.hex(eip55: isEipp55))"
                                    self.error("invoice.event", [errorMsg, self])
                                    self.emit(event: "error", args: [errorMsg])
                                    return
                                }
                                
                                guard invoiceSettledEvent.eventSignature == signatureHex else {
                                    let errorMsg = "Event signature not matched. received \(invoiceSettledEvent.eventSignature), expected: \(signatureHex)"
                                    self.error("invoice.event", [errorMsg, self])
                                    self.emit(event: "error", args: [errorMsg])
                                    return
                                }
                                
                                guard !invoiceSettledEvent.removed else {
                                    self.error("invoice.event", ["Invoice event were removed", self])
                                    self.emit(event: "error", args: ["Invoice event were removed"])
                                    return
                                }
                                
                                let invoice: [String: Any] = [
                                    "id": invoiceSettledEvent.id,
                                    "swap": [
                                        "id": invoiceSettledEvent.swap,
                                        "secret": invoiceSettledEvent.secret
                                    ],
                                    "payer": invoiceSettledEvent.payer,
                                    "payee": invoiceSettledEvent.payee,
                                    "asset": invoiceSettledEvent.asset,
                                    "quantity": invoiceSettledEvent.quantity
                                ]
                                
                                debug("Received secret from holder: \(String(describing: Utils.hexToData(invoiceSettledEvent.secret)))")
                                                                
                                self.info("invoice.settled", invoice)
                                self.emit(event: "invoice.settled", args: [invoice])
                            case .failure(let error):
                                self.error("error", [error, self])
                                self.emit(event: "error", args: [error])
                            }
                        }
                    default:
                        error("Unknow contract event", self)
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
            resolve(())
        }
    }
    
    func createInvoice(party: Party) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            guard let swap = party.swap, let secretHash = swap.secretHash else {
                return reject(SwapSDKError.msg("There is no swap or secret hash"))
            }
            
            debug("Creating invoice for \(party.partyType) with id: \(party.id)")
            
            guard let id = Utils.hexToData(secretHash) else {
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
                    guard let tx = self.contract["createInvoice"]?(params).createTransaction(
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
                                self.debug("ETH TH HASH: \(data.hex())")
                                
                                Thread.sleep(forTimeInterval: 0.5)
                                
                                self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                    guard let self = self else {
                                        return reject(SwapSDKError.msg("web3.eth.getTransactionReceipt self is nil"))
                                    }
                                    
                                    switch response.status {
                                    case .success(let txReceipt):
                                                                                
                                        let receipt = [
                                            "blockHash": txReceipt!.blockHash.hex(),
                                            "from": privKey.address.hex(eip55: false),
                                            "to": self.contract.address!.hex(eip55: false),
                                            "transactionHash": txReceipt!.transactionHash.hex()
                                        ]
                                        
                                        self.info("createInvoice", "partyId: \(party.id)", receipt)
                                        resolve(receipt)
                                    case .failure(let error):
                                        debug("ETH Fetching receip error: \(error)")
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
    
    func payInvoice(party: Party) -> Promise<[String: Any]> {
        Promise { [unowned self] resolve, reject in
            guard let swap = party.swap, let secretHash = swap.secretHash else {
                return reject(SwapSDKError.msg("There is no swap or secret hash"))
            }
            
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
                    guard let tx = self.contract["payInvoice"]?(params).createTransaction(
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
                                                                
                                Thread.sleep(forTimeInterval: 0.5)
                                
                                self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                    guard let self = self else {
                                        return reject(SwapSDKError.msg("web3.eth.getTransactionReceipt self is nil"))
                                    }
                                    
                                    switch response.status {
                                    case .success(let txReceipt):
                                                                                
                                        let receipt = [
                                            "blockHash": txReceipt!.blockHash.hex(),
                                            "from": privKey.address.hex(eip55: false),
                                            "to": self.contract.address!.hex(eip55: false),
                                            "transactionHash": txReceipt!.transactionHash.hex()
                                        ]
                                                                                
                                        self.info("payInvoice", "partyId: \(party.id)", receipt)
                                        resolve(receipt)
                                    case .failure(let error):
                                        debug("ETH Fetching receip error: \(error)")
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
                    guard let tx = self.contract["settleInvoice"]?(params).createTransaction(
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
                                
                                self.debug("Eth tx hash: \(data.hex())")
                                
                                Thread.sleep(forTimeInterval: 0.5)
                                
                                self.web3.eth.getTransactionReceipt(transactionHash: data) { [weak self] response in
                                    guard let self = self else {
                                        return reject(SwapSDKError.msg("web3.eth.getTransactionReceipt self is nil"))
                                    }
                                    switch response.status {
                                    case .success(let txReceipt):
                                        
                                        let receipt = [
                                            "blockHash": txReceipt!.blockHash.hex(),
                                            "from": privKey.address.hex(eip55: false),
                                            "to": self.contract.address!.hex(eip55: false),
                                            "transactionHash": txReceipt!.transactionHash.hex()
                                        ]
                                                                                
                                        self.info("settleInvoice", "partyId: \(party.id)", receipt)
                                        resolve(receipt)
                                    case .failure(let error):
                                        debug("ETH Fetching receip error: \(error)")
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
}
