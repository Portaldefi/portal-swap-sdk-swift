import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Ethereum: BaseClass, NativeChain {
    private let props: SwapSdkConfig.Blockchains.Ethereum
    
    private var web3: Web3!
    private var nativeLiquidity: INativeLiquidityManagerContract!
    private var invoiceManager: IInvoiceManagerContract!
    
    private var connected = false
    private let NATIVE_ADDRESS = "0x0000000000000000000000000000000000000000"
    
    var queue = TransactionLock()
            
    var address: String {
        props.traderAddress
    }
    
    init(props: SwapSdkConfig.Blockchains.Ethereum) {
        self.props = props
        
        web3 = Web3(rpcURL: props.url)
        print("Ethereum rpc client url: \(props.url)")
        
        super.init(id: "ethereum")
    }
    
    func start() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            let nativeLiquidityContractAddress = try DynamicContract.address(props.nativeLiquidityManagerContractAddress)
            nativeLiquidity = web3.eth.Contract(type: NativeLiquidityManagerContract.self, address: nativeLiquidityContractAddress)
            
            nativeLiquidity.watchContractEvents(
                interval: 3,
                onLogs: { [weak self] logs in
                    self?.onAccountingLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Native Liquidity Manager logs error", error)
                })
            
            print("(ETH) native liquidity address: \(nativeLiquidityContractAddress.hex(eip55: false))")
            
            let invoiceManagerContractAddress = try DynamicContract.address(props.invoiceManagerContractAddress)
            invoiceManager = web3.eth.Contract(type: InvoiceManagerContract.self, address: invoiceManagerContractAddress)
            
            print("(ETH) invoice manager address: \(invoiceManagerContractAddress.hex(eip55: false))")
            
            invoiceManager.watchContractEvents(
                interval: 3,
                onLogs: { [weak self] logs in
                    self?.onAccountingLogs(logs)
                },
                onError: { [weak self] error in
                    self?.debug("Invoice Manager logs error", error)
                })
            
            self.info("start")
            self.emit(event: "start")
            
            connected = true
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            self.connected = false
            
            nativeLiquidity.stopWatchingContractEvents()
            nativeLiquidity = nil
            
            invoiceManager.stopWatchingContractEvents()
            invoiceManager = nil
        }
    }
        
    func deposit(_ liquidity: Liquidity) -> Promise<Liquidity> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
            guard liquidity.chain == instanceId else {
                let expected = instanceId
                let actual = liquidity.chain
                let ctx = ["liquidity": liquidity]
                throw NativeChainError.invalidChain(expected: expected, actual: actual, context: ctx)
            }
            
            guard let assetAddress = EthereumAddress(hexString: liquidity.contractAddress) else {
                throw NativeChainError.init(message: "Invalid asset address", code: "404")
            }
            guard let portalAddress = EthereumAddress(hexString: liquidity.portalAddress) else {
                throw NativeChainError.init(message: "Invalid portal address", code: "404")
            }
            
            let quantity = (liquidity.contractAddress == NATIVE_ADDRESS) ? BigUInt(liquidity.nativeAmount) : 0
            let txValue: EthereumQuantity = EthereumQuantity(quantity: quantity)
            
            // Log starting deposit.
            debug("deposit.starting", [
                "contract": ["name": "accounting", "address": nativeLiquidity.address?.hex(eip55: false) ?? "unknown"],
                "args": [assetAddress.hex(eip55: false), liquidity.nativeAmount, portalAddress.hex(eip55: false)],
                "opts": ["value": txValue]
            ])
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid eth address", code: "404")
            }
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.nativeLiquidity.ethDeposit(
                        assetAddress: assetAddress,
                        nativeAmount: liquidity.nativeAmount,
                        nativeAddress: portalAddress
                    ).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 200_000),
                        from: swapOwner,
                        value: txValue,
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        throw NativeChainError.init(message: "Failed to create deposit transaction", code: "404")
                    }

                    print("deposit tx: \(tx)")
                    
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            print("deposit tx id: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
            
            print("Deposit receipt: \(receipt)")
            
            var depositedLiquidity: Liquidity?
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                    
                case NativeLiquidityManagerContract.Deposit.topic:
                    guard
                        let decoded = try? ABI.decodeLog(event: NativeLiquidityManagerContract.Deposit, from: log),
                        let id = decoded["id"] as? Data,
                        let chain = decoded["chain"] as? String,
                        let ts = decoded["ts"] as? BigUInt,
                        let symbol = decoded["symbol"] as? String,
                        let contractAddress = decoded["contractAddress"] as? EthereumAddress,
                        let nativeAmount = decoded["nativeAmount"] as? BigUInt,
                        let nativeAddress = decoded["nativeAddress"] as? EthereumAddress,
                        let portalAddress = decoded["portalAddress"] as? EthereumAddress,
                        let liquidity = try? Liquidity(
                            id: id.toHexString(),
                            ts: ts,
                            chain: chain,
                            symbol: symbol,
                            contractAddress: contractAddress.hex(eip55: true),
                            nativeAmount: BigInt(nativeAmount),
                            nativeAddress: nativeAddress.hex(eip55: true),
                            portalAddress: portalAddress.hex(eip55: true)
                        )
                    else {
                        throw NativeChainError(message: "Deposit event decoding error", code: "404")
                    }
                    
                    depositedLiquidity = liquidity
                default:
                    print("Unknown event topic: \(topic0.hex())")
                }
            }
            
            guard let depositedLiquidity else {
                throw NativeChainError(message: "Deposit event missing liquidity", code: "404")
            }
                        
            return depositedLiquidity
        }
    }
    
    func payInvoice(_ party: Party) -> Promise<Void> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError.init(message: "Invalid eth address", code: "404")
            }
            
            guard let swap = party.swap else {
                throw NativeChainError.init(message: "Swap is missing in party", code: "404")
            }
            
            let quantity = (party.contractAddress == NATIVE_ADDRESS) ? party.amount : 0
            let txValue: EthereumQuantity = EthereumQuantity(quantity: quantity)
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.invoiceManager.payInvoice(swap: swap).createTransaction(
                        nonce: nonce,
                        gasPrice: nil,
                        maxFeePerGas: EthereumQuantity(quantity: 100.gwei),
                        maxPriorityFeePerGas: EthereumQuantity(quantity: 2.gwei),
                        gasLimit: EthereumQuantity(quantity: 1_000_000),
                        from: swapOwner,
                        value: txValue,
                        accessList: [:],
                        transactionType: .eip1559
                    ) else {
                        throw NativeChainError.init(message: "Failed to create pay invoice transaction", code: "404")
                    }
                    
                    print("pay invoice tx: \(tx)")

                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            

            print("pay invoice tx id: \(txId)")
            party.receipt = txId
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
            
            print("Pay invoice receipt: \(receipt)")
            print("logs: \(receipt.logs)")
            
            guard !receipt.logs.isEmpty else {
                throw NativeChainError(message: "Pay invoice event missing logs", code: "404")
            }
        }
    }
    
    func createInvoice(_ party: Party) -> Promise<Invoice> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
                        
            debug("createInvoice.starting", [
                "contract": ["name": "invoiceManager", "address": invoiceManager.address?.hex(eip55: false) ?? "unknown"],
                "args": [party.swap]
            ])
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError(message: "Invalid eth address", code: "404")
            }
            
            guard let swap = party.swap else {
                throw NativeChainError(message: "Invalid swap", code: "404")
            }
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.invoiceManager.createInvoice(swap: swap).createTransaction(
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
                        throw NativeChainError(message: "Failed to create invoice transaction", code: "404")
                    }
                    
                    print("createInvoice tx: \(tx)")
                    
                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            print("createInvoice tx id: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
            
            print("CreateInvoice receipt: \(receipt)")
            
            // Extract event information from receipt
            var swapInvoice: String?
            
            for log in receipt.logs {
                guard let topic0 = log.topics.first else { continue }
                
                switch topic0 {
                case NativeLiquidityManagerContract.SwapInvoiceCreated.topic:
                    guard
                        let decoded = try? ABI.decodeLog(event: NativeLiquidityManagerContract.SwapInvoiceCreated, from: log)
                    else {
                        throw NativeChainError(message: "SwapInvoiceCreated event decoding error", code: "404")
                    }
                    
                    let swap = try Swap(json: decoded)
                    
                    // Get the correct invoice based on whether party is secretHolder
                    if try party.isSecretHolder() {
                        swapInvoice = swap.secretHolder.invoice
                    } else {
                        swapInvoice = swap.secretSeeker.invoice
                    }
                    
                default:
                    print("Unknown event topic: \(topic0.hex())")
                }
            }
            
            guard let swapInvoice else {
                throw NativeChainError(message: "SwapInvoiceCreated event missing or invoice not found", code: "404")
            }
            
            // Update party with invoice
//            party.invoice = swapInvoice
            
            info("createInvoice", ["party": party])
            
            return swapInvoice
        }
    }
    
    func settleInvoice(for party: Party, with secret: Data) -> Promise<Party> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
            
            guard let swap = party.swap else {
                throw NativeChainError(message: "Swap is missing in party", code: "404")
            }
            
            guard let swapOwner = EthereumAddress(hexString: address) else {
                throw NativeChainError(message: "Invalid eth address", code: "404")
            }
            
            let secretHex = "0x" + secret.hexString
            debug("settleInvoice.starting", swap.toJSON(), secretHex)
            
            let txId = try awaitPromise(withTxLock {
                self.web3.eth.getNonce(address: swapOwner).then { nonce in
                    guard let tx = self.invoiceManager.settleInvoice(
                        swap: swap,
                        secret: secret
                    ).createTransaction(
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
                        throw NativeChainError(message: "Failed to create invoice transaction", code: "404")
                    }
                    
                    print("settleInvoice tx: \(tx)")

                    let privKey = try EthereumPrivateKey(hexPrivateKey: self.props.privKey)
                    let signedTx = try tx.sign(with: privKey, chainId: EthereumQuantity.string(self.props.chainId))
                    
                    return self.web3.eth.publish(transaction: signedTx)
                }
            })
            
            print("settleInvoice tx id: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchReceipt(txHash: txIdData) })
            
            print("settleInvoice receipt: \(receipt)")
            
            guard !receipt.logs.isEmpty else {
                throw NativeChainError(message: "settleInvoice logs empty", code: "404")
            }
            
            return party
        }
    }
    
    private func onAccountingLogs(_ logs: [EthereumLogObject]) {
        for log in logs {
            do {
                try processLog(log)
            } catch {
                self.error("onAccountingLogs", error, ["log": log])
                emit(event: "error", args: [error, log])
            }
        }
    }

    private func processLog(_ log: EthereumLogObject) throws {
        guard let topic0 = log.topics.first else { return }
        guard let txHash = log.transactionHash else { return }
                
        switch topic0 {
        case NativeLiquidityManagerContract.Deposit.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.Deposit, from: log)
            
            let id = decoded["id"] as! Data
            let ts = decoded["ts"] as! BigUInt
            let chain = decoded["chain"] as! String
            let symbol = decoded["symbol"] as! String
            let contractAddress = decoded["contractAddress"] as! EthereumAddress
            let nativeAmount  = decoded["nativeAmount"] as! BigUInt
            let nativeAddress = decoded["nativeAddress"] as! EthereumAddress
            let portalAddress = decoded["portalAddress"] as! EthereumAddress
            
            print("Deposit event → id: \(id.hexString), ts: \(ts.description), chain: \(chain), symbol: \(symbol), contractAddress: \(contractAddress.hex(eip55: true)), nativeAmount: \(nativeAmount), nativeAddress: \(nativeAddress.hex(eip55: true)), portalAddress: \(portalAddress.hex(eip55: true))")
            
            let liquidity = try Liquidity(
                chain: chain,
                symbol: symbol,
                contractAddress: contractAddress.hex(eip55: false),
                nativeAmount: BigInt(nativeAmount),
                nativeAddress: nativeAddress.hex(eip55: false),
                portalAddress: portalAddress.hex(eip55: false)
            )
            
            emitOnFinality(txHash.hex(), event: "deposit", args: [liquidity])
            
        case NativeLiquidityManagerContract.Withdraw.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.Withdraw, from: log)
            
            let id = decoded["id"] as! Data
            let ts = decoded["ts"] as! BigUInt
            let chain = decoded["chain"] as! String
            let symbol = decoded["symbol"] as! String
            let contractAddress = decoded["contractAddress"] as! EthereumAddress
            let nativeAmount  = decoded["nativeAmount"] as! BigInt
            let nativeAddress = decoded["nativeAddress"] as! EthereumAddress
            let portalAddress = decoded["portalAddress"] as! EthereumAddress
            
            print("Withdraw event → id: \(id.hexString), ts: \(ts.description), chain: \(chain), symbol: \(symbol), nativeAmount: \(nativeAmount), nativeAddress: \(nativeAddress.hex(eip55: true)), portalAddress: \(portalAddress.hex(eip55: true))")
            
            let liquidity = try Liquidity(
                chain: chain,
                symbol: symbol,
                contractAddress: contractAddress.hex(eip55: false),
                nativeAmount: BigInt(nativeAmount),
                nativeAddress: nativeAddress.hex(eip55: false),
                portalAddress: portalAddress.hex(eip55: false)
            )
            
            emitOnFinality(txHash.hex(), event: "withdraw", args: [liquidity])
            
        case NativeLiquidityManagerContract.SwapHolderPaid.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.SwapHolderPaid, from: log)
            let id = decoded["id"] as! Data
            
            let swapHolderPaid = HolderPaidSwap(id: id.hexString, secretHolder: txHash.hex())
            print("SwapHolderPaid event → \(swapHolderPaid)")
            
            emitOnFinality(txHash.hex(), event: "swapHolderPaid", args: [swapHolderPaid])
            
        case NativeLiquidityManagerContract.SwapHolderSettled.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.SwapHolderSettled, from: log)
            let id = decoded["id"] as! Data
            let secret = decoded["secret"] as! Data
            
            let swapHolderSettled = HolderSettledSwap(id: id.hexString, secret: secret)
            print("SwapHolderSettled event → \(swapHolderSettled)")
            
            emitOnFinality(txHash.hex(), event: "swapHolderSettled", args: [swapHolderSettled])
            
        case NativeLiquidityManagerContract.SwapInvoiceCreated.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.SwapInvoiceCreated, from: log)
            let swap = try Swap(json: decoded)
            print("SwapInvoiceCreated event → \(swap)")
            
            emitOnFinality(txHash.hex(), event: "swapInvoiceCreated", args: [swap])
            
        case NativeLiquidityManagerContract.SwapSeekerPaid.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.SwapSeekerPaid, from: log)
            let id = decoded["id"] as! Data
            let seekerPaid = SeekerPaidSwap(id: id.hexString, secretSeeker: txHash.hex())
            
            print("SwapSeekerPaid event → \(seekerPaid)")
            
            emitOnFinality(txHash.hex(), event: "swapSeekerPaid", args: [seekerPaid])
            
        case NativeLiquidityManagerContract.SwapSeekerSettled.topic:
            let decoded = try ABI.decodeLog(event: NativeLiquidityManagerContract.SwapSeekerSettled, from: log)
            let id = decoded["id"] as! Data
            
            let seekerSettled = SeekerSettledSwap(id: id.hexString)
            print("SwapSeekerSettled event → \(seekerSettled)")

            emitOnFinality(txHash.hex(), event: "swapSeekerSettled", args: [seekerSettled])
            
        default:
            print("Unknown event topic: \(topic0.hex())")
        }
    }
}

extension Ethereum: TxLockable {
    internal func waitForReceipt(txid: String) -> Promise<Void> {
        Promise { [weak self] resolve, reject in
            guard let self else { throw SdkError.instanceUnavailable() }

            let txId = try EthereumData(ethereumValue: txid)
            
            waitForReceipt(hash: txId).then { _ in
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
    
    private func waitForReceipt(hash: EthereumData) -> Promise<EthereumTransactionReceiptObject> {
        retryWithBackoff { self.web3.eth.fetchReceipt(txHash: hash) }
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
