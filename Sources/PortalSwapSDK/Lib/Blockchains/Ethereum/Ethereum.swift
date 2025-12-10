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
    private var eventListener: ContractEventListener?

    private var connected = false
    private let NATIVE_ADDRESS = "0x0000000000000000000000000000000000000000"
    private let confirmations: Int

    var queue = TransactionLock()

    var address: String {
        props.traderAddress
    }

    init(props: SwapSdkConfig.Blockchains.Ethereum) {
        self.props = props
        
        let chainId = Int(props.chainId)!
        self.confirmations = Self.getConfsForNetwork(chainId)

        web3 = Web3(rpcURL: props.url)

        let nativeLiquidityContractAddress = try! DynamicContract.address(props.nativeLiquidityManagerContractAddress)
        nativeLiquidity = web3.eth.Contract(type: NativeLiquidityManagerContract.self, address: nativeLiquidityContractAddress)

        let invoiceManagerContractAddress = try! DynamicContract.address(props.invoiceManagerContractAddress)
        invoiceManager = web3.eth.Contract(type: InvoiceManagerContract.self, address: invoiceManagerContractAddress)

        super.init(id: "ethereum")

        info("Using \(confirmations) confirmations for chain \(props.chainId)")
    }

    private static func getConfsForNetwork(_ chainId: Int) -> Int {
        switch chainId {
        case 1337, 31337:
            return 1  // Local - minimal confirmations
        case 5, 11155111, 17000:
            return 4  // Testnet - balance of speed/reliability
        default:
            return 6  // Mainnet - matches updated safetyDepth
        }
    }
    
    func start(height: BigUInt) -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }

            let currentHeight = try awaitPromise(getCurrentBlockHeight())
            var startHeight = height

            if height == 0 {
                startHeight = currentHeight
                info("start: height was 0, starting from current block \(startHeight)")
            } else if height > currentHeight {
                startHeight = currentHeight
                warn("start: stored height > current height (network reset?), starting from current block", [
                    "storedHeight": height,
                    "currentHeight": currentHeight,
                    "startHeight": startHeight
                ])
            }

            let contracts = [
                ContractConfig(
                    address: nativeLiquidity.address!,
                    events: nativeLiquidity.events
                ),
                ContractConfig(
                    address: invoiceManager.address!,
                    events: invoiceManager.events
                )
            ]

            eventListener = ContractEventListener(
                web3: web3,
                contracts: contracts,
                initialBlock: startHeight,
                confirmations: confirmations
            )

            eventListener?.startPolling { [weak self] log in
                self?.onAccountingLog(log)
            }

            info("start: height=\(startHeight), confirmations=\(confirmations)")
            emit(event: "start")
            connected = true
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }

            eventListener?.stop()
            eventListener = nil
            connected = false

            info("stop")
        }
    }

    private func getCurrentBlockHeight() -> Promise<BigUInt> {
        Promise { [weak self] resolve, reject in
            self?.web3.eth.blockNumber { response in
                switch response.status {
                case .success(let blockNumber):
                    resolve(blockNumber.quantity)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }

    func getBlockHeight() -> Promise<UInt64> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }

            let blockNumber = try awaitPromise(getCurrentBlockHeight())
            info("getBlockHeight", ["blockNumber": blockNumber])
            return try UInt64(blockNumber)
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

            let invocation = nativeLiquidity.ethDeposit(
                assetAddress: assetAddress,
                nativeAmount: liquidity.nativeAmount,
                nativeAddress: portalAddress
            )

            let txId = try awaitPromise(
                withTxLock {
                    self.web3.eth.publishTransaction(
                        invocation: invocation,
                        privateKey: self.props.privKey,
                        chainId: self.props.chainId,
                        from: swapOwner,
                        value: txValue
                    )
                }
            )
            
            print("deposit tx id: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
            
            print("Deposit receipt status: \(String(describing: receipt.status))")
            
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

            let timeouts = calculateSwapTimeoutBlocks(
                secretHolderChain: swap.secretHolder.chain,
                secretSeekerChain: swap.secretSeeker.chain
            )
            swap.holderTimeoutBlock = BigUInt(timeouts.secretHolderTimeoutBlocks)
            swap.seekerTimeoutBlock = BigUInt(timeouts.secretSeekerTimeoutBlocks)

            let invocation = invoiceManager.payInvoice(swap: swap)

            let txId = try awaitPromise(
                withTxLock {
                    self.web3.eth.publishTransaction(
                        invocation: invocation,
                        privateKey: self.props.privKey,
                        chainId: self.props.chainId,
                        from: swapOwner,
                        value: txValue
                    )
                }
            )

            print("pay invoice tx id: \(txId)")
            party.receipt = txId
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
            
            print("Pay invoice receipt status: \(String(describing: receipt.status))")
            print("logs: \(receipt.logs.count)")
            
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

            let invocation = invoiceManager.createInvoice(swap: swap)

            let txId = try awaitPromise(
                withTxLock {
                    self.web3.eth.publishTransaction(
                        invocation: invocation,
                        privateKey: self.props.privKey,
                        chainId: self.props.chainId,
                        from: swapOwner
                    )
                }
            )
            
            print("createInvoice tx id: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(waitForReceipt(hash: txIdData))
            
            print("CreateInvoice receipt status: \(String(describing: receipt.status))")
            
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

            let invocation = invoiceManager.settleInvoice(swap: swap, secret: secret)

            let txId = try awaitPromise(
                withTxLock {
                    self.web3.eth.publishTransaction(
                        invocation: invocation,
                        privateKey: self.props.privKey,
                        chainId: self.props.chainId,
                        from: swapOwner
                    )
                }
            )
            
            print("settleInvoice tx id: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.fetchReceipt(txHash: txIdData) })
            
            print("settleInvoice receipt status: \(String(describing: receipt.status))")
            
            guard !receipt.logs.isEmpty else {
                throw NativeChainError(message: "settleInvoice logs empty", code: "404")
            }
            
            return party
        }
    }

    func fetchInvoiceTimeout(invoiceIdentifier: String) -> Promise<Int> {
        Promise { [weak self] resolve, reject in
            guard let self else {
                return reject(SdkError.instanceUnavailable())
            }

            invoiceManager.getSwapTimeout(swap: invoiceIdentifier).call { response, error in
                if let timeout = response?[""] as? BigUInt {
                    resolve(Int(timeout))
                } else if let error {
                    self.error("fetchInvoiceTimeout", error)
                    reject(error)
                } else {
                    let err = NativeChainError(message: "Failed to decode timeout", code: "404")
                    self.error("fetchInvoiceTimeout", err)
                    reject(err)
                }
            }
        }
    }

    private func parseLiquidityEvent(_ log: ProcessedLog) throws -> Liquidity {
        guard
            let chain = log.args["chain"] as? String,
            let symbol = log.args["symbol"] as? String,
            let contractAddress = log.args["contractAddress"] as? EthereumAddress,
            let nativeAmount = log.args["nativeAmount"] as? BigUInt,
            let nativeAddress = log.args["nativeAddress"] as? EthereumAddress,
            let portalAddress = log.args["portalAddress"] as? EthereumAddress
        else {
            throw NativeChainError(message: "Liquidity event parsing error", code: "404")
        }

        return try Liquidity(
            chain: chain,
            symbol: symbol,
            contractAddress: contractAddress.hex(eip55: false),
            nativeAmount: BigInt(nativeAmount),
            nativeAddress: nativeAddress.hex(eip55: false),
            portalAddress: portalAddress.hex(eip55: false)
        )
    }

    private func onAccountingLog(_ log: ProcessedLog) {
        do {
            let txHash = log.transactionHash
            let blockNumber = log.blockNumber

            switch log.eventName {
            case "Deposit":
                let liquidity = try parseLiquidityEvent(log)
                emitOnFinality(txHash, event: "deposit", args: [liquidity])

            case "Withdraw":
                let liquidity = try parseLiquidityEvent(log)
                emitOnFinality(txHash, event: "withdraw", args: [liquidity])

            case "SwapHolderPaid":
                let id = log.args["id"] as! Data
                let swapHolderPaid = HolderPaidSwap(id: id.hexString, secretHolder: txHash)
                emitOnFinality(txHash, event: "swapHolderPaid", args: [swapHolderPaid])

            case "SwapSeekerPaid":
                let id = log.args["id"] as! Data
                let seekerPaid = SeekerPaidSwap(id: id.hexString, secretSeeker: txHash)
                emitOnFinality(txHash, event: "swapSeekerPaid", args: [seekerPaid])

            case "SwapHolderSettled":
                let id = log.args["id"] as! Data
                let secret = log.args["secret"] as! Data
                let swapHolderSettled = HolderSettledSwap(id: id.hexString, secret: secret)
                emitOnFinality(txHash, event: "swapHolderSettled", args: [swapHolderSettled])

            case "SwapSeekerSettled":
                let id = log.args["id"] as! Data
                let seekerSettled = SeekerSettledSwap(id: id.hexString)
                emitOnFinality(txHash, event: "swapSeekerSettled", args: [seekerSettled])

            default:
                debug("accounting.on\(log.eventName)", log.args)
            }

            emit(event: "blockheight", args: [blockNumber])

        } catch {
            self.error("onAccountingLog", error, ["log": log])
            emit(event: "error", args: [error, log])
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
        retry(attempts: 10, delay: 3) {
            Promise {
                let confirmations = BigUInt(self.confirmations)
                let receipt = try awaitPromise(retry(attempts: 10, delay: 3) { self.web3.eth.fetchReceipt(txHash: hash) })
                let head = try awaitPromise(retry(attempts: 10, delay: 3) { self.web3.eth.blockNumber() })
                
                guard head.quantity >= receipt.blockNumber.quantity + confirmations else {
                    throw SdkError(message: "Not confirmed yet", code: String())
                }
                
                return receipt
            }
        }
    }
}

extension Ethereum {
    private func sign(transaction: EthereumTransaction) throws -> EthereumSignedTransaction {
        let privKey = try EthereumPrivateKey(hexPrivateKey: "\(props.privKey)")
        return try transaction.sign(with: privKey, chainId: EthereumQuantity.string(props.chainId))
    }
}
