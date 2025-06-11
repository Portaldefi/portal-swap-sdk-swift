import Foundation
import Promises
import Web3
import Web3ContractABI
import BigInt

final class Ethereum: BaseClass, IBlockchain {
    private let sdk: Sdk
    private let props: SwapSdkConfig.Blockchains.Ethereum
    
    private var web3: Web3!
    private var dex: IDexContract?
    private var liquidityProvider: ILiquidityProviderContract?
    
    private var subscriptionsIds = [String]()
    private var connected = false
    
    var dexContractAddress: String?
    var liquidityProviderContractAddress: String?
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Ethereum) {
        self.sdk = sdk
        self.props = props
        super.init(id: "ethereum")
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] in
            web3 = Web3(rpcURL: props.url)
    func start() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            let nativeLiquidityContractAddress = try DynamicContract.contractAddress(address: nativeLiquidityManagerContractAddress)
            let nativeLiquidityAbiData = try DynamicContract.contractAbiData(abi: nativeLiquidityAbi)
            nativeLiquidity = try web3.eth.Contract(json: nativeLiquidityAbiData, abiKey: nil, address: nativeLiquidityContractAddress)
            
            guard let nativeLiquidity else {
                throw SwapSDKError.msg("Ethereum cannot prepare contract")
            }
            
            print("(ETH) native liquidity address: \(nativeLiquidityContractAddress.hex(eip55: false))")
            
            print("Native liquidity methods")
            for method in nativeLiquidity.methods {
                print(method)
            }
            
            let invoiceManagerContractAddress = try DynamicContract.contractAddress(address: invoiceManagerContractAddress)
            let invoiceManagerAbiData = try DynamicContract.contractAbiData(abi: invoiceManagerAbi)
            invoiceManager = try web3.eth.Contract(json: invoiceManagerAbiData, abiKey: nil, address: invoiceManagerContractAddress)
            
            guard let invoiceManager else {
                throw SwapSDKError.msg("Ethereum cannot prepare contract")
            }
            
            print("(ETH) invoice manager address: \(invoiceManagerContractAddress.hex(eip55: false))")
            
            print("Invoice manager methods")
            for method in invoiceManager.methods {
                print(method)
            }
            
            let nativeLiquidityTopics = try DynamicContract.topics(contract: nativeLiquidity)
            let invoiceManagerTopics = try DynamicContract.topics(contract: invoiceManager)
            
            logPoller = RPCLogPoller(
                id: "Ethereum: Native liquidity & Invoice Manager",
                eth: web3!.eth,
                addresses: [nativeLiquidityContractAddress, invoiceManagerContractAddress],
                topics: [nativeLiquidityTopics + invoiceManagerTopics]
            ) { [weak self] logs in
                guard let self else { return }
                onAccountingLogs(logs)
            } onError: { error in
                print("Ethereum: Account manager logs error: \(error)")
            }

            logPoller?.startPolling(interval: 3)
            
            self.info("start")
            self.emit(event: "start")
            
            connected = true
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            connected = false
            nativeLiquidity = nil
        }
    }
    
    func swapOrder(secretHash: Data, order: SwapOrder) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let dex else {
                throw SwapSDKError.msg("Dex contract is nil")
            }
            
            guard let sellAsset = EthereumAddress(hexString: order.sellAddress) else {
                throw SwapSDKError.msg("Cannot unwrap sell asset address")
            }
                        
            let swapOwner = try publicAddress()
            let nonce = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.getNonce(address: swapOwner) })
            let quantity = EthereumQuantity(quantity: order.sellAmount)
            
            debug("swap order params", [
                "secretHash": "0x\(secretHash.hexString)",
                "sellAsset": sellAsset.hex(eip55: true),
                "sellAmount": order.sellAmount.description,
                "swapOwner": swapOwner.hex(eip55: true)
            ])
            
            let gasEstimation = try awaitPromise(retry(attempts: 3, delay: 2) { self.suggestedGasFees() })

            debug("swap order suggested medium fees: \(gasEstimation.medium)")
            
            let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
            let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxPriorityFeePerGas).gwei)
            
            guard let swapOrderTx = dex.swapOrder(
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
                throw SwapSDKError.msg("failed to build swap order tx")
            }
            
            let signedSwapOrderTx = try sign(transaction: swapOrderTx)
            let txId = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.publish(transaction: signedSwapOrderTx) })
            
            debug("swap order tx hash: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 5, delay: 10) { self.web3.eth.fetchReceipt(txHash: txIdData) })
            
            guard
                let log = receipt.logs.first,
                let orderCreatedEventFromLog = try? ABI.decodeLog(event: DexContract.OrderCreated, from: log),
                let secretHash = orderCreatedEventFromLog["secretHash"] as? Data,
                let sellAsset = orderCreatedEventFromLog["sellAsset"] as? EthereumAddress,
                let sellAmount = orderCreatedEventFromLog["sellAmount"] as? BigUInt,
                let swapOwner = orderCreatedEventFromLog["swapOwner"] as? EthereumAddress,
                let swapId = orderCreatedEventFromLog["swapId"] as? Data,
                let swapCreation = orderCreatedEventFromLog["swapCreation"] as? BigUInt
            else {
                return reject(SwapSDKError.msg("create swap tx failed"))
            }
            
            let orderCreatedEvent = OrderCreatedEvent(
                secretHash: secretHash.hexString,
                sellAsset: sellAsset.hex(eip55: true),
                sellAmount: sellAmount,
                swapOwner: swapOwner.hex(eip55: true),
                swapId: swapId.hexString,
                swapCreation: swapCreation
            )
            
            let receiptJson = [
                "blockHash": log.blockHash?.hex() ?? "?",
                "from": swapOrderTx.from?.hex(eip55: true) ?? "?",
                "to": swapOrderTx.to?.hex(eip55: true) ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded",
            ]
            
            info("create order event", [orderCreatedEventFromLog])
            info("create order tx receipt", [receiptJson])
            
            emit(event: "order.created", args: [orderCreatedEvent])
            
            resolve(receiptJson)
        }
    }
    
    func authorize(swapId: Data, withdrawals: [AuthorizedWithdrawal]) -> Promise<Response> {
        Promise { [unowned self] resolve, reject in
            guard let dex else {
                throw SwapSDKError.msg("Dex contract is nil")
            }
            
            debug("authorize params", [
                "swapId": swapId,
                "withdrawals": withdrawals
            ])
            
            let swapOwner = try publicAddress()
            let nonce = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.getNonce(address: swapOwner) })
            let gasEstimation = try awaitPromise(retry(attempts: 3, delay: 2) { self.suggestedGasFees() })
            
            debug("authorize suggested medium fees: \(gasEstimation.medium)")
            
            let maxFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxFeePerGas).gwei)
            let maxPriorityFeePerGas = EthereumQuantity(quantity: BigUInt(gasEstimation.medium.suggestedMaxPriorityFeePerGas).gwei)
            
            guard let authorizeTx = dex.authorize(
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
                throw SwapSDKError.msg("authorize tx build failed")
            }
            
            let signedAuthorizeTx = try sign(transaction: authorizeTx)
            let txId = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.publish(transaction: signedAuthorizeTx) })
            
            debug("authorize tx hash: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 5, delay: 10) { self.web3.eth.fetchReceipt(txHash: txIdData) })
            
            guard
                let log = receipt.logs.first,
                let authorizedEvent = try? ABI.decodeLog(event: DexContract.Authorized, from: log),
                let swapId = authorizedEvent["swapId"] as? Data
            else {
                return reject(SwapSDKError.msg("authorize tx failed"))
            }

            let logEvent = [
                "swapId": "0x\(swapId.hexString)"
            ]
            
            let receiptJson = [
                "blockHash": log.blockHash?.hex() ?? "?",
                "from": authorizeTx.from?.hex(eip55: true) ?? "?",
                "to": authorizeTx.to?.hex(eip55: true) ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded"
            ]
            
            let mergedReceipt = receiptJson.merging(logEvent) { (current, _) in current }
            info("authorize receip tx receipt", mergedReceipt)
            resolve(mergedReceipt)
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
            
            let nonce = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.getNonce(address: swapOwner) })
            let gasEstimation = try awaitPromise(retry(attempts: 3, delay: 2) { self.suggestedGasFees() })
            
            debug("settle invoice suggested medium fees: \(gasEstimation.medium)")
            
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
                return reject(SwapSDKError.msg("failed to build settle invoice tx"))
            }
            
            let signedSettleTx = try sign(transaction: settleTx)
            let txId = try awaitPromise(retry(attempts: 3, delay: 2) { self.web3.eth.publish(transaction: signedSettleTx) })

            debug("settle invoice tx hash: \(txId)")
            
            let txIdData = try EthereumData(ethereumValue: txId)
            let receipt = try awaitPromise(retry(attempts: 5, delay: 10) { self.web3.eth.fetchReceipt(txHash: txIdData) })
            
            guard
                let log = receipt.logs.first,
                let settleEvent = try? ABI.decodeLog(event: LiquidityProvider.InvoiceSettled, from: log),
                let swapId = settleEvent["swapId"] as? Data,
                let secret = settleEvent["secret"] as? Data,
                let counterParty = settleEvent["counterParty"] as? EthereumAddress,
                let sellAsset = settleEvent["sellAsset"] as? EthereumAddress,
                let sellAmount = settleEvent["sellAmount"] as? BigUInt
            else {
                return reject(SwapSDKError.msg("settle invoice tx failed"))
            }
            
            let logEvent = [
                "swapId": "0x\(swapId.hexString)",
                "secret": "0x\(secret.hexString)",
                "counterParty": "\(counterParty.hex(eip55: true))",
                "sellAsset": "\(sellAsset.hex(eip55: true))",
                "sellAmount": "\(sellAmount.description)"
            ]
            
            let receiptJson = [
                "blockHash": log.blockHash?.hex() ?? "?",
                "from": settleTx.from?.hex(eip55: true) ?? "?",
                "to": settleTx.to?.hex(eip55: true) ?? "?",
                "transactionHash": log.transactionHash?.hex() ?? "?",
                "status": "succeeded",
            ]
            
            let mergedReceipt = receiptJson.merging(logEvent) { (current, _) in current }
            info("settle event tx receipt", mergedReceipt, logEvent)
            
            if let mainId = invoice["mainId"] {
                emit(event: "invoice.settled", args: [swapIdHex, mainId])
            } else {
                emit(event: "invoice.settled", args: [swapIdHex])
            }
            
            resolve(mergedReceipt)
        }
    }
    
    func feePercentage() -> Promise<BigUInt> {
        Promise { [unowned self] resolve, reject in
            guard let dex else {
                return reject(SwapSDKError.msg("dex contract is missing"))
            }
            
            dex.feePercentage().call { response, error in
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
        Promise {}
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
