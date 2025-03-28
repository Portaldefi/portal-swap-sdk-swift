import Foundation
import Web3
import BigInt
import Promises

final class Dex: BaseClass {
    private var sdk: Sdk
    
    private var portal: Portal {
        sdk.blockchains.portal
    }
    
    private lazy var ethereum: Ethereum = {
        sdk.blockchains.ethereum
    }()
    
    private lazy var lightning: Lightning = {
        sdk.blockchains.lightning
    }()
        
    private(set) var order: SwapOrder?
    private var ethTxHash: String?
    
    var swapId: Data? = nil {
        willSet {
            if let newValue {
                debug("swapId set", newValue.hexString)
            }
        }
    }
    var secretHash: Data? = nil {
        willSet {
            if let newValue {
                debug("secret hash set", newValue.hexString)
            }
        }
    }
    
    init(sdk: Sdk) {
        self.sdk = sdk
        super.init(id: "dex")
        
        sdk.blockchains.on("error", forwardError())
        sdk.blockchains.on("order.created", onSwap("order.created"))
        sdk.blockchains.on("swap.created", onSwap("swap.created"))
        sdk.blockchains.on("swap.validated", onSwap("swap.validated"))
        sdk.blockchains.on("swap.matched", onSwap("swap.matched"))
        sdk.blockchains.on("invoice.paid", onSwap("invoice.paid"))
        sdk.blockchains.on("lp.invoice.created", onSwap("lp.invoice.created"))
        sdk.blockchains.on("invoice.settled", onSwap("invoice.settled"))
    }
    
    func open() -> Promise<Void> {
        Promise {()}
    }
    
    func close() -> Promise<Void> {
        Promise {
            self.order = nil
            self.secretHash = nil
            self.swapId = nil
            self.ethTxHash = nil
        }
    }
    
    func timeoutSwap() {        
        guard let swapId, let swap = try? sdk.store.getAmmSwap(key: swapId.hexString), swap.status != "completed" else {
            return
        }
        
        try? sdk.store.updateSwapStatus(id: swap.swapId.hexString, data: "failed:\(swap.status) timeout")
    }
    
    func submit(_ order: SwapOrder) -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            save(order: order)
            
            let (secret, secretHash) = Utils.createSecret()
            
            self.secretHash = secretHash
            
            switch order.sellNetwork {
            case "ethereum":
                //Secret holder
                try save(secret: secret, id: secretHash.hexString)
                                
                ethereum.swapOrder(
                    secretHash: secretHash,
                    order: order
                ).then { [unowned self] response in
                    info("order submitted", ["order": order, "response": response])
                    ethTxHash = response["transactionHash"]
                    resolve(())
                }.catch { swapOrderError in
                    reject(swapOrderError)
                }
            case "lightning":
                //Secret seeker
                portal.createSwap(
                    swapId: secretHash.hexString,
                    liquidityPoolId: order.poolId,
                    secretHash: secretHash.hexString,
                    sellAsset: order.sellAddress,
                    sellAmount: order.sellAmount,
                    buyAsset: order.buyAddress,
                    buyAmount: order.buyAmount,
                    slippage: 1000
                ).then { [unowned self] swap in
                    info("swap created", ["order": order, "swap": swap.toJSON()])
                    try sdk.store.create(swap: swap)
                    resolve(())
                }.catch { createSwapError in
                    reject(createSwapError)
                }
            default:
                reject(SwapSDKError.msg("Unsupported network: \(order.sellNetwork)"))
            }
        }
    }
}

extension Dex {
    private func save(order: SwapOrder) {
        self.order = order
    }
    
    private func save(secret: Data, id: String) throws {
        let secretDictionary = ["secret" : secret.hexString]
        try sdk.store.put(.secrets, id, secretDictionary)
    }
        
    private func onSwap(_ event: String) -> ([Any]) -> Void {
        { [unowned self] args in
            debug("\(event)", [args])
            
            switch event {
            case "order.created":
                guard let orderCreated = args.first as? OrderCreatedEvent else {
                    return throwError("order created event is missing", [args])
                }
                onOrderCreated(event: orderCreated)
            case "lp.invoice.created":
                guard let invoiceRegistered = args.first as? InvoiceRegisteredEvent else {
                    return throwError("invoice registered event is missing", [args])
                }
                onLpInvoiceCreated(event: invoiceRegistered)
            case "swap.matched":
                guard let swapMatched = args.first as? SwapMatchedEvent else {
                    return throwError("swap matched event is missing", [args])
                }
                onSwapMatched(event: swapMatched)
            case "invoice.paid":
                onInvoicePaid(args: args)
            case "invoice.settled":
                guard let swapId = args.first as? String else {
                    return throwError("invoice.settled swapId is missing", [args])
                }
                if let mainId = args.last as? String {
                    onInvoiceSettled(swapId: mainId)
                } else {
                    onInvoiceSettled(swapId: swapId)
                }
            default:
                warn("onSwap", ["Unsuppoted event": event])
            }
        }
    }
    
    private func onSwapMatched(event: SwapMatchedEvent) {
        guard let order else {
            return throwError("swap.matched order is missing", [event])
        }
        
        switch order.sellNetwork {
        case "ethereum":
            guard let swapOwner = try? ethereum.publicAddress() else {
                return throwError("invalid swap owner address", [event])
            }
            
            guard let swap = try? awaitPromise(portal.getSwap(id: event.swapId)) else {
                return throwError("create.invoice error", [error])
            }
            
            guard swap.swapOwner == swapOwner else {
                return info("On swap matched event received not owner")
            }
            
            let invoice = [
                "swapId": "0x" + swap.swapId.hexString,
                "secretHash": swap.secretHash.hexString,
                "quantity": event.matchedBuyAmount.description,
            ]
            
            debug("invoice", invoice)
            
            guard let traderBlockchain = sdk.blockchains.blockchain(id: order.buyNetwork) else {
                return throwError("\(order.buyNetwork) blockchain not found", [event])
            }
            
            traderBlockchain.create(invoice: invoice).then { [unowned self] invoice in
                info("trader.invoice.created", ["invoice": invoice])
                
                guard let invoice = invoice["request"] else {
                    throw SwapSDKError.msg("Cannot unwrap invoice")
                }
                
                try? self.sdk.store.updateBuyAssetTx(id: swap.swapId.hexString, data: invoice)
                
                return portal.registerInvoice(
                    swapId: swap.swapId,
                    secretHash: swap.secretHash,
                    amount: event.matchedBuyAmount,
                    invoice: invoice
                )
            }.then { [unowned self] result in
                all(
                    portal.getOutput(id: swap.secretHash.hexString),
                    ethereum.feePercentage()
                )
            }.then { [unowned self] output, fee in
                let feeAmount = (swap.sellAmount * fee) / BigUInt(10000)
                let amount = swap.sellAmount - feeAmount
                
                guard let matchedLpAddressHex = output["matchedLpAddress"] else {
                    throw SwapSDKError.msg("matchedLpAddressHex is invalid")
                }
                
                guard let matchedLpAddress = EthereumAddress(hexString: matchedLpAddressHex) else {
                    throw SwapSDKError.msg("matchedLpAddress is invalid")
                }
                
                let authorizedWithdrawal = AuthorizedWithdrawal(
                    addr: matchedLpAddress,
                    amount: amount
                )
                
                return ethereum.authorize(
                    swapId: swap.swapId,
                    withdrawals: [authorizedWithdrawal]
                )
            }.then { [unowned self] response in
                info("authorize call", ["response": response])
            }.catch { [unowned self] error in
                throwError("createInvoice", [error])
            }
        default:
            break
        }
    }
    
    private func onOrderCreated(event: OrderCreatedEvent) {
        guard let order else {
            return throwError("onSwap order is missing error", [event])
        }
        
        portal.createSwap(
            swapId: event.swapId,
            liquidityPoolId: order.poolId,
            secretHash: event.secretHash,
            sellAsset: order.sellAsset,
            sellAmount: event.sellAmount,
            buyAsset: order.buyAsset,
            buyAmount: order.buyAmount,
            slippage: 100
        ).then { [unowned self] swap in
            guard let ethTxHash else {
                return try sdk.store.create(swap: swap)
            }
            
            var swapToUpdate = swap
            swapToUpdate.sellAssetTx = ethTxHash
            
            try sdk.store.create(swap: swapToUpdate)
        }.catch { [unowned self]  error in
            throwError("[Portal] Swap creation error", [error])
        }
    }
    
    private func onLpInvoiceCreated(event: InvoiceRegisteredEvent) {
        guard let order else {
            return throwError("onSwap order is missing error", [event])
        }
        
        switch order.sellNetwork {
        case "lightning":
            guard let swap = try? awaitPromise(portal.getSwap(id: event.swapId)) else {
                return throwError("paying ln invoice error", "unknown swap")
            }
            
            do {
                let response = try awaitPromise(portal.getOutput(id: event.secretHash))
                
                guard
                    let matcheedBuyAmount = response["matchedBuyAmount"],
                    let invoice = response["invoice"]
                else {
                    throw SwapSDKError.msg("getOutput unexpected response")
                }
                
                let request = [
                    "swapId": event.swapId,
                    "quantity": matcheedBuyAmount.description,
                    "request": invoice
                ]
                
                debug("LP invoice", request)
                
                try? sdk.store.updateBuyAssetTx(id: swap.swapId.hexString, data: event.invoice)
                
                let result = try awaitPromise(lightning.pay(invoice: request))
                debug("LP invoice paid", result)
            } catch {
                throwError("paying ln invoice error", [error])
            }
        default:
            break
        }
    }
    
    private func onInvoicePaid(args: [Any]) {
        guard let order else {
            return throwError("onSwap order is missing error", [args])
        }
        
        let _swapId: String
        var _secret: Data?
        
        switch order.sellNetwork {
        case "lightning":
            guard let swapId = args[2] as? String else {
                return throwError("swapId not passed with", [args])
            }
            _swapId = swapId
            
            if let secretHex = args[1] as? String {
                _secret = Data(hex: secretHex)
            } else {
                return throwError("Secret is unknown")
            }
        default:
            guard let swapId = args.first as? String else {
                return throwError("swapId is missing", [args])
            }
            _swapId = swapId
        }
        
        guard let swap = try? awaitPromise(portal.getSwap(id: _swapId)) else {
            return throwError("settle invoice error", "unknown swap")
        }
        
        guard let swapOwner = try? ethereum.publicAddress() else {
            return throwError("swap owner is unknown", [order])
        }
        
        guard swap.swapOwner == swapOwner else {
            return debug("On invoice paid received not owner")
        }
        
        let secret: Data
        let swapId: String
        
        var json = [String: String]()
        
        if let _secret {
            secret = _secret
            swapId = swap.secretHash.hexString
            json["mainId"] = _swapId
        } else {
            guard
                let _secret = try? sdk.store.get(.secrets, swap.secretHash.hexString)["secret"] as? Data
            else {
                return throwError("OnInvoicePaid secret is missing", [swap])
            }
            secret = _secret
            swapId = _swapId
        }
        
        json["swapId"] = swapId
        
        guard let traderBlockchain = sdk.blockchains.blockchain(id: order.buyNetwork) else {
            return throwError("(\(order.buyNetwork) blockchain is missing", [order])
        }
        
        traderBlockchain.settle(invoice: json, secret: secret).then { response in
            self.info("invoice.settled", response)
        }.catch { error in
            self.throwError("settle invoice error", [error])
        }
    }
    
    private func onInvoiceSettled(swapId: String) {
        guard let swapOwner = try? ethereum.publicAddress() else {
            return throwError("OnInvoiceSettled", ["swap owner is unknown"])
        }
        
        guard let swap = try? awaitPromise(portal.getSwap(id: swapId)) else {
            return throwError("onInvoiceSettled error - unknown swap")
        }
        
        guard swap.swapOwner == swapOwner else {
            return debug("onInvoiceSettled event received not owner")
        }
        
        emit(event: "swap.completed", args: [swapId])
        
        try? sdk.store.updateSwapStatus(id: swap.swapId.hexString, data: "completed")
    }
    
    func throwError(_ event: String, _ arguments: Any...) {
        guard let swapId, let swap = try? awaitPromise(portal.getSwap(id: swapId.hexString)) else {
            return error(event, arguments)
        }

        try? sdk.store.updateSwapStatus(id: swap.swapId.hexString, data: "failed:\(event)")
        
        error(event, arguments)
    }
}
