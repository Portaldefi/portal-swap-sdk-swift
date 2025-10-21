import Foundation
import Promises
import BigInt

final class Sdk: BaseClass {
    let store: Store
    let portalChain: Portal
    private(set) var nativeChains = [String: NativeChain]()
    
    private var depositTimeoutTimer: Timer?
    private let depositTimeoutInterval: TimeInterval = 60*5
    
    init(config: SwapSdkConfig) {
        store = Store(accountId: config.id)
            
        let requiredChains = Set([config.sellAsset, config.buyAsset])
        
        for chainKey in requiredChains {
            switch chainKey {
            case "ethereum":
                nativeChains[chainKey] = Ethereum(props: config.blockchains.ethereum) as NativeChain
            case "lightning":
                nativeChains[chainKey] = Lightning(props: config.blockchains.lightning) as NativeChain
            case "solana":
                nativeChains[chainKey] = Solana(props: config.blockchains.solana) as NativeChain
            default:
                break
            }
        }
        
        portalChain = Portal(props: config.blockchains.portal)
        
        super.init(id: "sdk")
        
        portalChain
            .on("log", onLog())
            .on("error", onError())
            .on("swapMatched", onSwapEvent())
            .on("swapHolderInvoiced", onSwapEvent())
            .on("swapSeekerInvoiced", onSwapEvent())
        
        for nativeChain in nativeChains.values {
            nativeChain
                .on("log", onLog())
                .on("error", onError())
                .on("swapHolderPaid", onSwapEvent())
                .on("swapSeekerPaid", onSwapEvent())
                .on("swapHolderSettled", onSwapEvent())
                .on("swapSeekerSettled", onSwapEvent())
        }

    }
    
    func portalAddress() -> String {
        portalChain.address
    }
    
    func nativeAddress(chain: String) throws -> String {
        guard let nativeChain = nativeChains[chain] else {
            throw SdkError.invalidChain(chain: chain)
        }
        return nativeChain.address
    }
    
    func start() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            try awaitPromise(portalChain.start())
            try awaitPromise(store.start())
            
            for nativeChain in nativeChains.values {
                try awaitPromise(nativeChain.start())
            }
        }
    }

    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            try awaitPromise(portalChain.stop())
            try awaitPromise(store.stop())

            for nativeChain in nativeChains.values {
                try awaitPromise(nativeChain.stop())
            }
        }
    }
    
    private func onLog() -> ([Any]) -> Void {
        return { [weak self] args in
            guard let self = self else { return }
            
            guard args.count >= 2,
                  let level = args[0] as? String,
                  let event = args[1] as? String else {
                return
            }
            
            let extraArgs = Array(args.dropFirst(2))
            
            // Switch on the log level string.
            switch level.lowercased() {
            case "debug":
                self.debug(event, extraArgs)
            case "info":
                self.info(event, extraArgs)
            case "warn":
                self.warn(event, extraArgs)
            case "error":
                self.error(event, extraArgs)
            default:
                self.warn("Unknown log level", level, extraArgs)
            }
        }
    }
    
    private func onError() -> ([Any]) -> Void {
        return { [weak self] args in
            guard let self = self else { return }
            self.error("unhandledError", args)
        }
    }
    
    private func onSwapEvent() -> ([Any]) -> Void {
        return { [weak self] args in
            guard let self = self else { return }
            
            var swap: Swap
            
            switch args.first {
            case let swapObject as Swap:
                guard swapObject.hasParty(portalChain.address) else { return }
                
                if swapObject.state == .matched {
                    // New matched swap - check for collision
                    do {
                        swap = try store.get(swapId: swapObject.id)
                        return
                    } catch let error as StoreError where error.code == "ENotFound" {
                        // Swap doesn't exist, proceed
                        swap = swapObject
                    } catch {
                        self.error("onSwapEvent", error, swapObject)
                        return
                    }
                    
                    // Ensure the swap pertains to the current user
                    if !swapObject.hasParty(portalChain.address) {
                        let err = SwapSDKError.msg("unknown swap for this party!")
                        self.warn("onSwapEvent", err, swapObject)
                        return
                    }
                    
                    // Save new swap
                    do {
                        try store.put(swap: swap)
                    } catch {
                        self.error("onSwapEvent", "Failed to save swap to store", swap.toJSON(), error)
                        return
                    }
                } else {
                    // Non-matched state - update existing swap
                    do {
                        swap = try store.get(swapId: swapObject.id)
                        try swap.updateFromSwap(swapObject)
                        try store.update(swap: swap)
                    } catch {
                        self.error("onSwapEvent", "Failed to update swap", swapObject, error)
                        return
                    }
                }
                
            case let swapDiff as SwapDiff:
                debug("onSwapEvent.diff", swapDiff)
                
                do {
                    swap = try store.get(swapId: swapDiff.id)
                    try swap.update(swapDiff)
                    try store.update(swap: swap)
                } catch {
                    self.warn("onSwapEvent", "Failed to retrieve/update swap from store", swapDiff, error)
                    return
                }
                
            default:
                self.error("Invalid swap event", args)
                return
            }
            
            debug("onSwapEvent.swap", swap.toJSON())
            
            switch swap.state {
            case .matched:
                onSwapMatched(swap: swap)
            case .holderInvoiced:
                swapHolderInvoiced(swap: swap)
            case .seekerInvoiced:
                swapSeekerInvoiced(swap: swap)
            case .holderPaid:
                swapHolderPaid(swap: swap)
            case .seekerPaid:
                swapSeekerPaid(swap: swap)
            case .holderSettled:
                swapHolderSettled(swap: swap)
            case .seekerSettled:
                swapSeekerSettled(swap: swap)
            }
        }
    }
        
    private func onSwapMatched(swap: Swap) {
        guard swap.state == .matched else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.isSecretSeeker(portalChain.address) {
            info("onSwapMatched", { swap })
            emit(event: "swapMatched", args: [swap])
            return
        }
        
        if !swap.isSecretHolder(portalChain.address) {
            emit(event: "error", args: ["unknown swap for this party"])
            return
        }
        
        info("onSwapMatched", swap.toJSON())
        emit(event: "swapMatched", args: [swap])
        
        do {
            let secretHashString = try store.createSecret()
            swap.secretHash = "0x" + secretHashString
            
            guard let nativeChain = nativeChains[swap.secretSeeker.chain] else {
                emit(event: "error", args: [SdkError.invalidChain(chain: swap.secretSeeker.chain)])
                return
            }
                        
            swap.secretSeeker.invoice = try awaitPromise(nativeChain.createInvoice(swap.secretSeeker))
            try? awaitPromise(portalChain.registerInvoice(swap))
        } catch {
            self.error("onSwapMatched", "Failed to create or register invoice", error)
        }
    }
    
    private func swapHolderInvoiced(swap: Swap) {
        guard swap.state == .holderInvoiced else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.secretSeeker.invoice == nil {
            emit(event: "error", args: ["missing secret holder invoice!", swap.toJSON()])
            return
        }
        
        if swap.isSecretHolder(portalChain.address) {
            info("onSwapHolderInvoiced", { swap })
            emit(event: "swapHolderInvoiced", args: [swap])
            return
        }
        
        if !swap.isSecretSeeker(portalChain.address) {
            emit(event: "error", args: ["Unknown swap for this party!", swap.toJSON()])
            return
        }
        
        info("onSwapHolderInvoiced", { swap })
        emit(event: "swapHolderInvoiced", args: [swap])
        
        let secretHolder = swap.secretHolder
        
        guard let nativeChain = nativeChains[secretHolder.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: secretHolder.chain)])
            return
        }
        
        do {
            secretHolder.invoice = try awaitPromise(nativeChain.createInvoice(secretHolder))
            try awaitPromise(portalChain.registerInvoice(swap))
        } catch {
            emit(event: "error", args: ["Failed to create or register invoice", error])
        }
    }
    
    private func swapSeekerInvoiced(swap: Swap) {
        guard swap.state == .seekerInvoiced else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.secretHolder.invoice == nil {
            emit(event: "error", args: ["missing secret seeker invoice!", swap.toJSON()])
            return
        }
        
        if swap.isSecretSeeker(portalChain.address) {
            info("onSwapSeekerInvoiced", { swap })
            emit(event: "swapSeekerInvoiced", args: [swap])
            return
        }
        
        if !swap.isSecretHolder(portalChain.address) {
            emit(event: "error", args: ["Unknown swap for this party!", swap.toJSON()])
            return
        }
        
        let secretHolder = swap.secretHolder
        
        guard let nativeChain = nativeChains[secretHolder.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: secretHolder.chain)])
            return
        }
        
        info("onSwapSeekerInvoiced", { swap })
        emit(event: "swapSeekerInvoiced", args: [swap])
        
        do {
            try awaitPromise(nativeChain.payInvoice(secretHolder))
        } catch {
            emit(event: "error", args: ["Failed to pay invoice", error])
        }
    }
    
    private func swapHolderPaid(swap: Swap) {
        guard swap.state == .holderPaid else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.secretHolder.receipt == nil {
            emit(event: "error", args: ["missing secret holder's invoice!", swap.toJSON()])
            return
        }
        
        if swap.isSecretHolder(portalChain.address) {
            info("onSwapHolderPaid", { swap })
            emit(event: "swapHolderPaid", args: [swap])
            return
        }
        
        if !swap.isSecretSeeker(portalChain.address) {
            emit(event: "error", args: ["Unknown swap for this party!", swap.toJSON()])
            return
        }
         
        info("onSwapHolderPaid", swap.toJSON())
        emit(event: "swapHolderPaid", args: [swap])
        
        guard let nativeChain = nativeChains[swap.secretSeeker.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: swap.secretSeeker.chain)])
            return
        }
        
        do {
            try awaitPromise(nativeChain.payInvoice(swap.secretSeeker))
        } catch {
            self.error("onSwapHolderPaid", "Failed to pay invoice", error)
        }
    }
    
    private func swapSeekerPaid(swap: Swap) {
        guard swap.state == .seekerPaid else {
            let err = SwapSDKError.msg("invalid swap state: \(swap.state)")
            self.error("onSwapSeekerPaid", { err })
            return
        }
        
        if swap.secretSeeker.receipt == nil {
            let err = SwapSDKError.msg("missing secret seeker's receipt!")
            self.error("onSwapSeekerPaid", { err })
            return
        }
        
        if swap.isSecretSeeker(portalChain.address) {
            info("onSwapSeekerPaid", { swap })
            emit(event: "swapSeekerPaid", args: [swap])
            return
        }
        
        if !swap.isSecretHolder(portalChain.address) {
            let err = SwapSDKError.msg("Unknown swap for this party!")
            self.error("onSwapSeekerPaid", { err })
            return
        }
        
        info("onSwapSeekerPaid", swap.toJSON())
        emit(event: "swapSeekerPaid", args: [swap])
        
        guard let secret = try? store.getSecret(key: swap.secretHash) else {
            emit(event: "error", args: ["missing secret!", swap.toJSON()])
            return
        }
        
        guard let nativeChain = nativeChains[swap.secretSeeker.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: swap.secretHolder.chain)])
            return
        }
        
        do {
            let party = try awaitPromise(nativeChain.settleInvoice(for: swap.secretSeeker, with: secret))
            print("party: \(party)")
        } catch {
            emit(event: "error", args: ["Failed to settle invoice", error])
        }
    }
    
    private func swapHolderSettled(swap: Swap) {
        guard swap.state == .holderSettled else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.isSecretHolder(portalChain.address) {
            info("onSwapHolderSettled", { swap })
            emit(event: "swapHolderSettled", args: [swap])
            return
        }
        
        if !swap.isSecretSeeker(portalChain.address) {
            emit(event: "error", args: ["Unknown swap for this party!", swap.toJSON()])
            return
        }
        
        info("onSwapHolderSettled", swap.toJSON())
        emit(event: "swapHolderSettled", args: [swap])
        
        guard let nativeChain = nativeChains[swap.secretHolder.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: swap.secretHolder.chain)])
            return
        }
        
        guard let secret = swap.secret else {
            emit(event: "error", args: [SdkError.init(message: "Secret is missing", code: "EInvalidSecret")])
            return
        }
        
        do {
            let party = try awaitPromise(nativeChain.settleInvoice(for: swap.secretHolder, with: secret))
            print("party: \(party)")
        } catch {
            emit(event: "error", args: ["Failed to settle invoice", error])
        }
    }
    
    private func swapSeekerSettled(swap: Swap) {
        guard swap.state == .seekerSettled else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.isSecretHolder(portalChain.address) {
            info("onSwapSeekerSettled", swap)
            emit(event: "swapSeekerSettled", args: [swap])
        } else if swap.isSecretSeeker(portalChain.address) {
            info("onSwapSeekerSettled", swap)
            emit(event: "swapSeekerSettled", args: [swap])
        } else {
            emit(event: "error", args: ["Unknown swap for this party!", swap.toJSON()])
        }
    }
        
    // Liquidity operations
    
    func deposit(chain: String, symbol: String, amount: BigInt) -> Promise<Liquidity> {
        Promise { [weak self] resolve, reject in
            guard let self else { throw SdkError.instanceUnavailable() }
            guard let nativeChain = nativeChains[chain] else { throw SdkError.invalidChain(chain: chain) }
            
            let asset = try awaitPromise(portalChain.retrieveAsset(chain: chain, symbol: symbol))
            
            var liquidity = try Liquidity(
                chain: asset.chain,
                symbol: asset.symbol,
                contractAddress: asset.contractAddress,
                nativeAmount: amount,
                nativeAddress: nativeChain.address,
                portalAddress: portalChain.address
            )
            
            debug("deposit.starting", try liquidity.toJSON())
            liquidity = try awaitPromise(nativeChain.deposit(liquidity))
            
            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timeoutTimer.schedule(deadline: .now() + depositTimeoutInterval, repeating: .never)
            timeoutTimer.setEventHandler {
                timeoutTimer.cancel()
                reject(SdkError.timedOut(context: ["liquidity": liquidity]))
            }
            timeoutTimer.resume()
                        
            portalChain.on("AssetMinted") { [weak self] args in
                guard let self = self else { return }
                guard let deposit = args[0] as? Liquidity else { return }
                
                debug("deposit", deposit, liquidity)
                    
                guard liquidity.equals(deposit) else { return }
                
                timeoutTimer.cancel()

                portalChain.off("AssetMinted")
                
                resolve(liquidity)
            }
        }
    }
    
    func withdraw(chain: String, symbol: String, amount: BigInt) -> Promise<Liquidity> {
        Promise { [weak self] resolve, reject in
            guard let self else { throw SdkError.instanceUnavailable() }
            guard let nativeChain = nativeChains[chain] else { throw SdkError.invalidChain(chain: chain) }
            
            // Retrieve the asset from the portal chain.
            let asset = try awaitPromise(portalChain.retrieveAsset(chain: chain, symbol: symbol))
            
            let liquidity = try Liquidity(
                chain: asset.chain,
                symbol: asset.symbol,
                contractAddress: asset.contractAddress,
                nativeAmount: -amount,
                nativeAddress: nativeChain.address,
                portalAddress: portalChain.address
            )
            
            debug("withdraw.starting", liquidity)
            let burnedLiquidity = try awaitPromise(portalChain.burnAsset(liquidity))
            debug("withdraw.waiting", burnedLiquidity)
            
            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timeoutTimer.schedule(deadline: .now() + depositTimeoutInterval, repeating: .never)
            timeoutTimer.setEventHandler {
                timeoutTimer.cancel()
                reject(SdkError.timedOut(context: ["liquidity": liquidity]))
            }
            timeoutTimer.resume()
                        
            nativeChain.on("withdraw") { [weak self] args in
                guard let self = self else { return }
                guard let withdraw = args[0] as? Liquidity else { return }
                
                debug("withdraw", withdraw, liquidity)
                    
                guard liquidity.equals(withdraw) else { return }
                
                timeoutTimer.cancel()

                portalChain.off("withdraw")
                
                resolve(liquidity)
            }
        }
    }
    
    // Market operations
    
    func openOrder(sellChain: String, sellSymbol: String, sellAmount: BigInt, buyChain: String, buySymbol: String, buyAmount: BigInt, orderType: Order.OrderType) -> Promise<Order> {
        Promise { [weak self]  in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            if nativeChains[sellChain] == nil {
                throw SdkError.invalidChain(chain: sellChain)
            }
            
            if nativeChains[buyChain] == nil {
                throw SdkError.invalidChain(chain: buyChain)
            }
            
            if sellAmount <= 0 {
                throw SdkError.invalidOrder(sellChain, sellSymbol, sellAmount)
            }
            
            let ptb = portalChain
            
            let sellAssetId: String
            do {
                let sellAsset = try awaitPromise(ptb.retrieveAsset(chain: sellChain, symbol: sellSymbol))
                sellAssetId = sellAsset.id
            } catch {
                throw SdkError.invalidAsset(chain: sellChain, symbol: sellSymbol, cause: error)
            }
            
            let buyAssetId: String
            do {
                let buyAsset = try awaitPromise(ptb.retrieveAsset(chain: buyChain, symbol: buySymbol))
                buyAssetId = buyAsset.id
            } catch {
                throw SdkError.invalidAsset(chain: buyChain, symbol: buySymbol, cause: error)
            }
            
            let order = try Order(
                trader: portalAddress(),
                sellAsset: sellAssetId,
                sellAmount: sellAmount,
                buyAsset: buyAssetId,
                buyAmount: buyAmount,
                orderType: orderType
            )
            
            do {
                debug("openOrder.starting", ["order": order.toJSON()])
                try awaitPromise(ptb.openOrder(order))
                info("openOrder", ["order": order.toJSON()])
                return order
            } catch {
                throw SdkError(message: "Open order error", code: "P2B", context: ["order": order.toJSON()], cause: error)
            }
        }
    }
        
}

final class SdkError: BaseError {
    static func instanceUnavailable() -> SdkError {
        let message = "InstanceUnavailable!"
        let code = "EInvalidInstance"
        return SdkError(message: message, code: code, context: [:])
    }
    
    /// Reports an invalid native chain selection.
    static func invalidChain(chain: String) -> SdkError {
        let message = "Invalid native chain \(chain)!"
        let code = "EInvalidChain"
        let context: [String: Any] = ["chain": chain]
        return SdkError(message: message, code: code, context: context)
    }
    
    /// Reports an invalid order.
    static func invalidOrder(_ chain: String, _ symbol: String, _ amount: BigInt) -> SdkError {
        let message = "Invalid order on \(chain) for \(amount) \(symbol)!"
        let code = "EInvalidChain"
        let context: [String: Any] = ["chain": chain]
        return SdkError(message: message, code: code, context: context)
    }
    
    /// Reports an invalid asset selection.
    static func invalidAsset(chain: String, symbol: String, cause: Error) -> SdkError {
        let message = "Invalid asset \(chain).\(symbol)!"
        let code = "EInvalidAsset"
        let context: [String: Any] = ["chain": chain, "symbol": symbol]
        return SdkError(message: message, code: code, context: context, cause: cause)
    }
    
    /// Reports an invalid receipt from a party.
    static func invalidReceipt(party: Party) -> SdkError {
        let message = "Invalid receipt!"
        let code = "EInvalidReceipt"
        let context: [String: Any] = ["party": party]
        return SdkError(message: message, code: code, context: context)
    }
    
    /// Reports an error on a specific native chain.
    static func nativeChainError(chain: String, context: [String: Any], cause: Error) -> SdkError {
        let message = "Error on \(chain) chain!"
        let code = "ENativeChainError"
        return SdkError(message: message, code: code, context: context, cause: cause)
    }
    
    /// Reports an error on the portal chain.
    static func portalChainError(context: [String: Any], cause: Error) -> SdkError {
        let message = "Error on portal chain!"
        let code = "EPortalChainError"
        return SdkError(message: message, code: code, context: context, cause: cause)
    }
    
    /// Reports a timeout waiting for an operation to complete.
    static func timedOut(context: [String: Any]) -> SdkError {
        let message = "Operation timed out!"
        let code = "ETimedOut"
        return SdkError(message: message, code: code, context: context)
    }
        
    override init(message: String, code: String, context: [String: Any]? = nil, cause: Error? = nil) {
        super.init(message: message, code: code, context: context, cause: cause)
    }
}
