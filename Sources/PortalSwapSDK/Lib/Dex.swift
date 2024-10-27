import Foundation
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
        
        subscribe(sdk.blockchains.on("error", forwardError()))
        subscribe(sdk.blockchains.on("order.created", onSwap("order.created")))
        subscribe(sdk.blockchains.on("swap.created", onSwap("swap.created")))
        subscribe(sdk.blockchains.on("swap.validated", onSwap("swap.validated")))
        subscribe(sdk.blockchains.on("swap.matched", onSwap("swap.matched")))
        subscribe(sdk.blockchains.on("invoice.paid", onSwap("invoice.paid")))
        subscribe(sdk.blockchains.on("lp.invoice.created", onSwap("lp.invoice.created")))
        subscribe(sdk.blockchains.on("invoice.settled", onSwap("invoice.settled")))
    }
    
    func open() -> Promise<Void> {
        Promise {()}
    }
    
    func close() -> Promise<Void> {
        Promise {
            self.order = nil
            self.secretHash = nil
            self.swapId = nil
        }
    }
    
    func submit(_ order: SwapOrder) -> Promise<Void> {
        Promise { [unowned self] in
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
                    return info("order submitted", ["order": order, "response": response])
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
                ).then { [unowned self] response in
                    return info("notary.createSwap", ["order": order, "response": response])
                }
            default:
                throw SwapSDKError.msg("Unsupported network: \(order.sellNetwork)")
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
                    return error("order created event is missing", [args])
                }
                onOrderCreated(event: orderCreated)
            case "lp.invoice.created":
                guard let invoiceRegistered = args.first as? InvoiceRegisteredEvent else {
                    return error("invoice registered event is missing", [args])
                }
                onLpInvoiceCreated(event: invoiceRegistered)
            case "swap.matched":
                guard let swapMatched = args.first as? SwapMatchedEvent else {
                    return error("swap matched event is missing", [args])
                }
                onSwapMatched(event: swapMatched)
            case "invoice.paid":
                onInvoicePaid(args: args)
            case "invoice.settled":
                guard let swapId = args.first as? String else {
                    return error("onInvoiceSettled swapId is missing error", [args])
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
            return error("onSwapMatched", [event])
        }
        guard let traderBlockchain = sdk.blockchains.blockchain(id: order.buyNetwork) else {
            return error("blockchain with id: \(order.buyNetwork) not found", [event])
        }
        guard let swapOwner = try? ethereum.publicAddress() else {
            return error("swap owner is unknown", [event])
        }

        portal.getSwap(id: event.swapId).then { swap in
            guard swap.swapOwner == swapOwner else {
                return self.warn("On swap matched event received not owner")
            }
                        
            switch order.sellNetwork {
            case "ethereum":
                let invoice = [
                    "swapId": "0x" + swap.swapId.hexString,
                    "secretHash": swap.secretHash.hexString,
                    "quantity": event.matchedBuyAmount.description,
                ]
                
                self.debug("invoice", invoice)

                traderBlockchain.create(invoice: invoice).then { [unowned self] invoice in
                    info("trader.invoice.created", ["invoice": invoice])
                    
                    guard let invoice = invoice["request"] else {
                        throw SwapSDKError.msg("Cannot unwrap invoice")
                    }
                                        
                    return portal.registerInvoice(
                        swapId: swap.swapId,
                        secretHash: swap.secretHash,
                        amount: event.matchedBuyAmount,
                        invoice: invoice
                    )
                }.then { [unowned self] result in
                    ethereum.feePercentage()
                }.then { [unowned self] fee in
                    let feeAmount = (swap.sellAmount * fee) / BigUInt(10000)
                    let amount = swap.sellAmount - feeAmount
                    let publicAddress = try ethereum.publicAddress()
                    
                    let authorizedWithdrawal = AuthorizedWithdrawal(
                        addr: publicAddress,
                        amount: amount
                    )
                    
                    return ethereum.authorize(
                        swapId: swap.swapId,
                        withdrawals: [authorizedWithdrawal]
                    )
                }.then { [unowned self] response in
                    info("authorize call", ["response": response])
                }.catch { [unowned self] error in
                    self.error("createInvoice", [error])
                }
            default:
                break
            }
        }
    }
    
    private func onOrderCreated(event: OrderCreatedEvent) {
        guard let order else {
            return error("onSwap order is missing error", [event])
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
        ).catch { error in
            self.error("[Portal] Swap creation error", [error])
        }
    }
    
    private func onLpInvoiceCreated(event: InvoiceRegisteredEvent) {
        guard let order else {
            return error("onSwap order is missing error", [event])
        }
        
        switch order.sellNetwork {
        case "lightning":
            portal.getOutput(id: event.swapId).then { [unowned self] response in
                guard
                    let matcheedBuyAmount = response["matchedBuyAmount"],
                    let invoice = response["invoice"]
                else {
                    throw SwapSDKError.msg("getOutput: Unexpected response")
                }

                let request = [
                    "swapId": event.swapId,
                    "quantity": matcheedBuyAmount.description,
                    "request": invoice
                ]
                
                debug("LP invoice", request)
                
                return lightning.pay(invoice: request)
            }.catch { error in
                self.error("paying ln invoice error", [error])
            }
        default:
            break
        }
    }
    
    private func onInvoicePaid(args: [Any]) {
        guard let order else {
            return error("onSwap order is missing error", [args])
        }
        guard let traderBlockchain = sdk.blockchains.blockchain(id: order.buyNetwork) else {
            return error("traderBlockchain (\(order.buyNetwork) is missing", [order])
        }
        guard let swapOwner = try? ethereum.publicAddress() else {
            return error("swap owner is unknown", [order])
        }
        
        let _swapId: String
        var _secret: Data?
        
        switch order.sellNetwork {
        case "lightning":
            guard let swapId = args[2] as? String else {
                return error("swapId not passed with", [args])
            }
            _swapId = swapId
            
            if let secretHex = args[1] as? String {
                _secret = Data(hex: secretHex)
            } else {
                return error("Secret is unknown")
            }
        default:
            guard let swapId = args.first as? String else {
                return error("swapId is missing", [args])
            }
            _swapId = swapId
        }
        
        portal.getSwap(id: _swapId).then { [unowned self] swap in
            guard swap.swapOwner == swapOwner else {
                return self.warn("On invoice paid received not owner")
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
                    return error("OnInvoicePaid secret is missing", [swap])
                }
                secret = _secret
                swapId = _swapId
            }
            
            json["swapId"] = swapId
                        
            return traderBlockchain.settle(invoice: json, secret: secret)
        }.then { [unowned self] response in
            info("invoice.settled", response)
        }.catch { error in
            self.debug("settleInvoice(party: party, secret: secret)", error)
            self.error("error", [error])
        }
    }
    
    private func onInvoiceSettled(swapId: String) {
        guard let swapOwner = try? ethereum.publicAddress() else {
            return error("OnInvoiceSettled", ["swap owner is unknown"])
        }
        
        portal.getSwap(id: swapId).then { [unowned self] swap in
            guard swap.swapOwner == swapOwner else {
                return self.warn("onInvoiceSettled event received not owner")
            }
            emit(event: "swap.completed", args: [swapId])
            try sdk.store.put(.swaps, swapId, swap.toJSON())
        }.catch { [unowned self] error in
            self.error("cannot fetch swap with id: \(swapId)")
        }
    }
}
