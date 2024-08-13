import Foundation
import Promises

final class Dex: BaseClass {
    private var sdk: Sdk
//    private var ammSwap: AmmSwap?
    
    init(sdk: Sdk) {
        self.sdk = sdk
        super.init(id: "dex")
        
        subscribe(sdk.blockchains.on("trader.intent.created", onSwap("trader.intent.created")))
        subscribe(sdk.blockchains.on("notary.validator.match.intent", onSwap("notary.validator.match.intent")))
        subscribe(sdk.blockchains.on("invoice.paid", onSwap("invoice.paid")))
        subscribe(sdk.blockchains.on("invoice.settled", onSwap("invoice.settled")))
    }
    
    // Opens the orderbooks
    func open() -> Promise<Void> {
        Promise {()}
    }
    
    // Closes the orderbooks
    func close() -> Promise<Void> {
        Promise {()}
    }
    
    func onSwap(_ event: String) -> ([Any]) -> Void {
        { [unowned self] args in
            switch event {
            case "trader.intent.created":
                debug("trader.intent.created", args)
                
                guard let swapIntendedEvent = args.first as? SwapIntendedEvent else {
                    return
                }
                
                let ammSwap = AmmSwap.from(swapIntendedEvent: swapIntendedEvent)
                
                try? sdk.store.put(.swaps, ammSwap.swapId, ammSwap.toJSON())
                
                emit(event: "dex.\(ammSwap.status)", args: [ammSwap])
            case "notary.validator.match.intent":
                debug("notary.validator.match.intent", args)
                                
                guard let swapmatchedEvent = args.first as? SwapMatchedEvent else { return }
                guard let swap = try? sdk.store.getAmmSwap(key: swapmatchedEvent.swapId) else { return }
                guard let traderBlockchain = sdk.blockchains.blockchain(id: swap.buyNetwork) else { return }
                                
                let party = createParty(swap: swap, swapMatchedEvent: swapmatchedEvent)
                
                swap.status = event
                swap.buyQuantity = party.quantity
                
                try? sdk.store.update(.swaps, swapmatchedEvent.swapId, swap.toJSON())
                                
                traderBlockchain.createInvoice(party: party).then { invoice in
                    self.info("trader.invoice.created", invoice)
                    
                    self.sdk
                        .blockchains
                        .portal
                        .registerInvoice(swapId: "\(swap.swapId)", invoice: invoice["request"]! as String)
                        .then { result in
                            self.info("notary.register.invoice", result)
                        }.catch { error in
                            self.debug("notary.register.invoice error", error)
                            self.error("error", error)
                        }
                }.catch { error in
                    self.debug("createInvoice(party: \(party)", error)
                    self.error("error", error)
                }
            case "invoice.paid":
                guard let swapId = args.first as? String else { return }
                guard let swap = try? sdk.store.getAmmSwap(key: swapId) else { return }
                
                swap.status = event
                try? sdk.store.update(.swaps, swapId, swap.toJSON())
                
                guard let secret = try? sdk.store.get(.secrets, swap.secretHash)["secret"] as? Data else { return }
                guard let traderBlockchain = sdk.blockchains.blockchain(id: swap.buyNetwork) else { return }
                
                let party = Party(id: "trader", quantity: Int64(1), swap: swap)
                
                traderBlockchain.settleInvoice(party: party, secret: secret)
                    .then { response in
                        self.info("invoice.settled", response)
                    }.catch { error in
                        self.debug("settleInvoice(party: party, secret: secret)", error)
                        self.error("error", error)
                    }
            case "invoice.settled":
                guard let swapId = args.first as? String else { return }
                guard let swap = try? sdk.store.getAmmSwap(key: swapId) else { return }
                
                swap.status = "completed"
                try? sdk.store.update(.swaps, swapId, swap.toJSON())
                
                self.emit(event: "swap.completed")
            default:
                print("Unsupported event")
            }
        }
    }
    
    func createParty(swap: AmmSwap, swapMatchedEvent: SwapMatchedEvent) -> Party {
        let ethMultiplier: Decimal = Decimal(string: "1e18")!
        let btcMultiplier: Decimal = Decimal(string: "1e8")!
        let conversionFactor = ethMultiplier / btcMultiplier
        
        let matchedBuyAmountDecimal = Decimal(string: swapMatchedEvent.matchedBuyAmount.description)!
        let newAmount = matchedBuyAmountDecimal / conversionFactor
        
        let quantity = Int64(floor(NSDecimalNumber(decimal: newAmount).doubleValue))
        return Party(id: "trader", quantity: quantity, swap: swap)
    }
    
    func submitOrder(_ request: OrderRequest) -> Promise<[String : String]> {
        Promise { [unowned self] resolve, reject in
            let secretHash = Utils.sha256(data: request.secret)
            let secretDictionary = ["secret" : request.secret.toHexString()]
            try sdk.store.put(.secrets, secretHash.toHexString(), secretDictionary)
            
            let traderBuyId = UInt64.random(in: 1000...100_000_000)
            let buyAmount = UInt64(request.buyQuantity)
            let sellAmount = UInt64(request.sellQuantity)
            let buyAmountSlippage = UInt64(1)
            
            let buyAddress: String
            let sellAddress: String
            
            switch request.sellNetwork {
            case "ethereum":
                buyAddress = "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
                sellAddress = "0x0000000000000000000000000000000000000000"
                
                guard let traderBlockchain = sdk.blockchains.blockchain(id: request.sellNetwork) else {
                    return reject(SwapSDKError.msg("sdk.blockchains.blockchain(id: \(request.sellNetwork)) is failed"))
                }
                
                let intent = SwapIntent(
                    secretHash: secretHash,
                    traderBuyId: traderBuyId,
                    buyAmount: buyAmount,
                    buyAddress: buyAddress,
                    sellAmount: sellAmount,
                    sellAddress: sellAddress,
                    buyAmountSlippage: buyAmountSlippage
                )
                
                traderBlockchain.swapIntent(intent)
                    .then { [weak self] response in
                        self?.info("processSwap", response)

                        resolve(response)
                    }.catch { [weak self] error in
                        self?.debug("traderBlockchain.swapIntent(\(intent))\n error: \(error)")
                        self?.error("error", [error])
                        
                        reject(error)
                    }
            case "lightning":
                buyAddress = "0x0000000000000000000000000000000000000000"
                sellAddress = "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
                                
                let intent = SwapIntent(
                    secretHash: secretHash,
                    traderBuyId: traderBuyId,
                    buyAmount: buyAmount,
                    buyAddress: buyAddress,
                    sellAmount: sellAmount,
                    sellAddress: sellAddress,
                    buyAmountSlippage: buyAmountSlippage
                )
                
                sdk.blockchains.portal.swapIntent(intent)
                    .then { [weak self] response in
                        self?.info("processSwap", response)

                        resolve(response)
                    }.catch { [weak self] error in
                        self?.debug("notary blockchain.swapIntent(\(intent))\n error: \(error)")
                        self?.error("error", [error])
                        
                        reject(error)
                    }
            default:
                return reject(SwapSDKError.msg("unsupported sell network: \(request.sellNetwork)"))
            }
        }
    }
}
