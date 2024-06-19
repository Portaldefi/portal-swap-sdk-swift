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
    private var portalADMMContract: DynamicContract!
    
    private var subscriptionsIDS = [String]()
    private let subscriptionAccessQueue = DispatchQueue(label: "swap.sdk.subscriptionAccessQueue")
    
    // Sdk seems unused
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Portal) {
        self.sdk = sdk
        self.props = props
        super.init(id: "Portal")
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
                    return reject(SwapSDKError.msg("Portal cannot prepare contract"))
                }
                
                let portalADMMContractAddresisEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
                
                let portalADMMContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: portalADMMContractAddresisEipp55)
                let portalADMMContractData = try JSONSerialization.data(withJSONObject: abiArray, options: [])
                
                portalADMMContract = try web3.eth.Contract(json: portalADMMContractData, abiKey: nil, address: portalADMMContractAddress)
                                
                //notaryADMM contract subscriptions
                for (index, event) in portalADMMContract.events.enumerated() {
                    print(event.name)
                    
                    let signatureHex = "0x\(Utils.keccak256Hash(of: event.signature))"
                    let addresses = [portalADMMContractAddress]
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
                                debug("\(sdk.userId) SwapIntended subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { (response: Web3Response<SwapMatchedEvent>) in
                            print("SwapMatchedEvent: \(response)")
                            
                            let status = "notary.validator.match.intent"
                            self.info(status, [response])
                            self.emit(event: status, args: [response])
                        }
                    case "InvoiceRegistered":
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
                                debug("\(sdk.userId) SwapIntended subscription failed with error: \(error)")
                                self.error("error", [error, self])
                            }
                        } onEvent: { (response: Web3Response<InvoiceRegisteredEvent>) in
                            print("InvoiceRegisteredEvent: \(response)")
                            let status = "invoice.registered"
                            self.info(status, [response])
                            self.emit(event: status, args: [response])
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
    
    func registerInvoice(swapId: Data, invoice: String) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            let params = SolidityTuple([
                SolidityWrappedValue(value: swapId, type: .bytes(length: 32)),
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
                                        
                    guard let tx = self.portalADMMContract["registerInvoice"]?(params).createTransaction(
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
                                                "to": self.portalADMMContract.address!.hex(eip55: false),
                                                "transactionHash": txReceipt.transactionHash.hex()
                                            ]
                                            
                                            self.info("registerLpInvoice", receipt, self as Any)
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
    
    func registerSwap(intent: SwapIntent) -> Promise<[String: String]> {
        Promise { resolve, reject in }
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

