//
//  Portal.swift
//  
//
//  Created by farid on 06.06.2024.
//

import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Portal: BaseClass, IBlockchain {
    private let sdk: Sdk
    private let props: SwapSdkConfig.Blockchains.Portal
    
    private var web3: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    private var admmContract: DynamicContract!

    private var subscriptionsIDS = [String]()
    private let subscriptionAccessQueue = DispatchQueue(label: "swap.sdk.subscriptionAccessQueue")
    
    // Sdk seems unused
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
                    let abiArray = contract["abi"] as? [[String: Any]],
                    let contractAddressHex = contract["address"] as? String
                else {
                    return reject(SwapSDKError.msg("Portal cannot prepare NotaryADMM contract"))
                }
                
                let admmContractAddresIsEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
                
                let admmContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: admmContractAddresIsEipp55)
                let admmContractData = try JSONSerialization.data(withJSONObject: abiArray, options: [])
                
                admmContract = try web3.eth.Contract(json: admmContractData, abiKey: nil, address: admmContractAddress)
                                
                //notaryADMM contract subscriptions
                for (index, event) in admmContract.events.enumerated() {
                    print(event.name)
                    
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
                    case "SwapMatched":
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
                                debug("\(sdk.userId) SwapMatched subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { [weak self] (response: Web3Response<SwapMatchedEvent>) in
                            guard let self = self else {
                                return reject(SwapSDKError.msg("SwapMatchedEvent self is nil"))
                            }
                            
                            switch response.status {
                            case .success(let event):
                                print("SwapMatchedEvent: \(event)")

                                let status = "notary.validator.match.order"
                                
                                self.info(status, [event])
                                self.emit(event: status, args: [event])
                            case .failure(let error):
                                debug("\(sdk.userId) SwapMatched subscription event fail error: \(error)")
                                self.error("error", [error, self])
                            }
                        }
//                    case "SwapRegistered":
//                        websocketProvider.subscribe(request: request) { [weak self] response in
//                            guard let self = self else {
//                                return reject(SwapSDKError.msg("SwapRegistered self is nil"))
//                            }
//                            
//                            switch response.status {
//                            case .success(let subscriptionID):
//                                self.subscriptionAccessQueue.async {
//                                    self.subscriptionsIDS.append(subscriptionID)
//                                }
//                            case .failure(let error):
//                                debug("\(sdk.userId) SwapRegistered subscription failed with error: \(error)")
//                                self.error("error", [error, self])
//                            }
//                        } onEvent: { [weak self] (response: Web3Response<SwapRegisteredEvent>) in
//                            guard let self = self else {
//                                return reject(SwapSDKError.msg("SwapRegistered self is nil"))
//                            }
//                            
//                            switch response.status {
//                            case .success(let event):
//                                print("SwapRegistered: \(event)")
//
//                                let status = "notary.validator.match.intent"
//                                
//                                self.info(status, [event])
//                                self.emit(event: status, args: [event])
//                            case .failure(let error):
//                                debug("\(sdk.userId) SwapMatched subscription event fail error: \(error)")
//                                self.error("error", [error, self])
//                            }
//                        }
                    default:
                        continue
                    }
                }
                
                for method in admmContract.methods {
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
    
    func registerInvoice(swapId: String, invoice: String) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            guard let id = Utils.hexToData(swapId) else {
                return reject(SwapSDKError.msg("Cannot convert id"))
            }
            
            let params = SolidityTuple([
                SolidityWrappedValue(value: id, type: .bytes(length: 32)),
                SolidityWrappedValue(value: invoice, type: .string)
            ])
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    debug("PRTL create invoice nonce: \(nonce.quantity)")
                    
                    guard let tx = self.admmContract["registerInvoice"]?(params).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 300_000),
                        from: privKey.address,
                        value: EthereumQuantity(quantity: 0),
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
                                self.debug("register invoice TH HASH: \(data.hex())")
                                
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
                                                "to": self.admmContract.address!.hex(eip55: false),
                                                "transactionHash": txReceipt.transactionHash.hex()
                                            ]
                                            
                                            self.info("registerLpInvoice", receipt, txReceipt)
                                            resolve(receipt)
                                        }
                                    case .failure(let error):
                                        print("Register invoice receip error: \(error)")
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
    
    func swapIntent(_ intent: SwapIntent) -> Promise<[String : String]> {
        Promise { [unowned self] resolve, reject in
            guard let sellAsset = EthereumAddress(hexString: intent.sellAddress) else {
                return reject(SwapSDKError.msg("Cannot unwrap sell asset address"))
            }
            
            guard let buyAsset = EthereumAddress(hexString: intent.buyAddress) else {
                return reject(SwapSDKError.msg("Cannot unwrap buy asset address"))
            }
                        
            let swapId = intent.secretHash
            let traderBuyId = BigUInt(intent.traderBuyId.makeBytes())
            let sellAmount = BigUInt(intent.sellAmount.makeBytes())
            let buyAmount = BigUInt(intent.buyAmount.makeBytes())
            let buyAmountSlippage = BigUInt(intent.buyAmountSlippage.makeBytes())
            let sellAssetChainId = BigUInt(UInt64(0).makeBytes())
            let buyAssetChainId = BigUInt(UInt64(1).makeBytes())
            let poolFee = BigUInt(UInt64(0).makeBytes())
            
            let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
            
            guard let swapOwner = EthereumAddress(hexString: privKey.address.hex(eip55: false)) else {
                return reject(SwapSDKError.msg("Cannot unwrap buy asset address"))
            }
                        
            let params = SolidityTuple([
                SolidityWrappedValue(value: traderBuyId, type: .uint256),
                SolidityWrappedValue(value: sellAsset, type: .address),
                SolidityWrappedValue(value: sellAssetChainId, type: .uint256),
                SolidityWrappedValue(value: sellAmount, type: .uint256),
                SolidityWrappedValue(value: buyAsset, type: .address),
                SolidityWrappedValue(value: buyAssetChainId, type: .uint256),
                SolidityWrappedValue(value: poolFee, type: .uint256),
                SolidityWrappedValue(value: buyAmount, type: .uint256),
                SolidityWrappedValue(value: buyAmountSlippage, type: .uint256),
                SolidityWrappedValue(value: swapId, type: .bytes(length: 32)),
                SolidityWrappedValue(value: swapOwner, type: .address)
            ])
                        
            web3.eth.getTransactionCount(address: privKey.address, block: .latest, response: { [weak self] response in
                guard let self = self else {
                    return reject(SwapSDKError.msg("web3.eth.getTransactionCount self is nil"))
                }
                
                switch response.status {
                case .success(let nonce):
                    debug("PRTL create invoice nonce: \(nonce.quantity)")
                    
                    guard let tx = self.admmContract["registerSwapIntent"]?(params).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 300_000),
                        from: privKey.address,
                        value: EthereumQuantity(quantity: 0),
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
                                self.debug("register invoice TH HASH: \(data.hex())")
                                
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
                                                "to": self.admmContract.address!.hex(eip55: false),
                                                "transactionHash": txReceipt.transactionHash.hex()
                                            ]
                                            
                                            self.info("registerLpInvoice", receipt, txReceipt)
                                            resolve(receipt)
                                        }
                                    case .failure(let error):
                                        print("Register invoice receip error: \(error)")
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
        Promise { resolve, reject in }
    }
    
    func payInvoice(party: Party) -> Promise<[String: Any]> {
        Promise { resolve, reject in }
    }
    
    func settleInvoice(party: Party, secret: Data) -> Promise<[String: String]> {
        Promise { resolve, reject in }
    }
}

