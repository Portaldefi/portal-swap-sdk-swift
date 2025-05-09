import Foundation
import Promises
import BigInt


public final class Sdk: BaseClass {
    private let store: Store
    private(set) var portalChain: Portal
    private(set) var nativeChains = [String: NativeChain]()
    
    private var depositTimeoutTimer: Timer?
    
    public init(config: SwapSdkConfig) {
        DispatchQueue.promises = .global(qos: .userInitiated)

        store = Store(accountId: "TestAccountId")
        
        portalChain = Portal(props: config.blockchains.portal)
        nativeChains = [
            "ethereum": Ethereum(props: config.blockchains.ethereum) as NativeChain,
            "lightning": Lightning(props: config.blockchains.lightning) as NativeChain,
            "solana": Solana(props: config.blockchains.solana) as NativeChain
        ]
        
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
        return nativeChain.address.lowercased()
    }
    
    func start() async throws {
        try await portalChain.start()
        try await store.start()
        
        for nativeChain in nativeChains.values {
            try await nativeChain.start()
        }
    }

    func stop() async throws {
        try await portalChain.stop()
        try await store.stop()
        
        for nativeChain in nativeChains.values {
            try await nativeChain.stop()
        }
    }
    
    private func onLog() -> ([Any]) -> Void {
        return { [weak self] args in
            guard let self = self else { return }
            
            // Ensure we have at least the log level and event in the arguments.
            guard args.count >= 2,
                  let level = args[0] as? String,
                  let event = args[1] as? String else {
                return
            }
            
            // Any extra arguments after the first two.
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
            guard let swapDiff = args.first as? Swap else {
                return error("Invalid swap event", args)
            }
            
            debug("onSwapEvent", swapDiff)
            
            let swap: Swap
            if swapDiff.state == .matched {
                // When the swap is matched, we ensure that the swap is not already in the
                // store. If it is, we throw an error. This is a defensive workaround to
                // prevent any potential collisions.
                guard ((try? store.get(swapId: swapDiff.id)) == nil) else {
                    self.error("onSwapEvent", "Swap already exists in store", swapDiff)
                    self.emit(event: "error", args: ["error: Swap already exists in store \(swapDiff)"])
                    return
                }
                
                swap = swapDiff
                
                // Ensure the swap pertains to the current user
                guard swapDiff.hasParty(portalChain.address) else {
                    let err = SdkError.invalidReceipt(party: swapDiff.secretHolder)
                    self.warn("onSwapEvent", err, { swapDiff })
                    self.emit(event: "error", args: [err, swapDiff])
                    return
                }
                
                // The swap is new, so we need to save it to the store. If it fails,
                // we throw an error.
                
                do {
                    try store.put(swap: swap)
                    print("Store swap in storage: \(swap.toJSON())")
                } catch {
                    self.error("onSwapEvent", "Failed to save swap to store", swap)
                    self.emit(event: "error", args: ["Failed to save swap to store \(swap)"])
                    return
                }
            } else {
                do {
                    swap = try store.get(swapId: swapDiff.id)
                    try swap.update(swapDiff)
                    try store.update(swap: swap)
                } catch {
                    self.error("onSwapEvent", "Failed to retrieve swap from store", swapDiff)
                    self.emit(event: "error", args: ["Failed to retriever swap from store \(swapDiff)"])
                    return
                }
            }

            
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
                swapHolderSettled(swap: swap)
            }
        }
    }
        
    private func onSwapMatched(swap: Swap) {
        // ensure the swap is in the correct state
        guard swap.state == .matched else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        // The SecretSeeker does not have anything to do at this point. Simply log
        // and emit the event.
        guard !swap.isSecretSeeker(portalChain.address) else {
            info("onSwapMatched", { swap })
            emit(event: "swapMatched", args: [swap])
            return
        }
        
        guard swap.isSecretHolder(portalChain.address) else {
            emit(event: "error", args: ["unknown swap for this party"])
            return
        }
        
        info("onSwapMatched", swap.toJSON())
        emit(event: "swapMatched", args: [swap])
                
        guard let nativeChain = nativeChains[swap.secretSeeker.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: swap.secretSeeker.chain)])
            return
        }
        
        do {
            let secretHash = try store.createSecret()
            try swap.setSecretHash(secretHash)
                        
            swap.secretSeeker.invoice = try awaitPromise(nativeChain.createInvoice(swap.secretSeeker))
            try? awaitPromise(portalChain.registerInvoice(swap))
        } catch {
            emit(event: "error", args: ["Failed to create or register invoice", error])
        }
    }
    
    private func swapHolderInvoiced(swap: Swap) {
        guard swap.state == .holderInvoiced else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        guard swap.secretSeeker.invoice != nil else {
            emit(event: "error", args: ["missing secret seeker invoice!", swap.toJSON()])
            return
        }
        
        guard !swap.isSecretHolder(portalChain.address) else {
            return
        }
        
        guard swap.isSecretSeeker(portalChain.address) else {
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
            swap.secretHolder.invoice = try awaitPromise(nativeChain.createInvoice(secretHolder))
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
        
        guard swap.secretHolder.invoice != nil else {
            emit(event: "error", args: ["missing secret holder's invoice!", swap.toJSON()])
            return
        }
        
        if swap.isSecretSeeker(portalChain.address) {
            return
        }
        
        guard swap.isSecretHolder(portalChain.address) else {
            emit(event: "error", args: ["Unknown swap for this party!", swap.toJSON()])
            return
        }
        
        let secretHolder = swap.secretHolder
        
        guard let nativeChain = nativeChains[secretHolder.chain] else {
            emit(event: "error", args: [SdkError.invalidChain(chain: secretHolder.chain)])
            return
        }
        
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
        
        guard swap.secretHolder.receipt != nil else {
            emit(event: "error", args: ["missing secret holder's invoice!", swap.toJSON()])
            return
        }
        
        if swap.isSecretHolder(portalChain.address) {
            info("onSwapHolderPaid", { swap })
            emit(event: "swapHolderPaid", args: [swap])
            return
        }
        
        if !swap.isSecretHolder(portalChain.address) {
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
            emit(event: "error", args: ["Failed to pay invoice", error])
        }
    }
    
    private func swapSeekerPaid(swap: Swap) {
        guard swap.state == .seekerPaid else {
            emit(event: "error", args: ["Invalid swap state", swap.toJSON()])
            return
        }
        
        if swap.secretSeeker.receipt == nil {
            emit(event: "error", args: ["missing secret seeker receipt!", swap.toJSON()])
            return
        }
        
        if !swap.isSecretHolder(portalChain.address) {
            emit(event: "error", args: ["unknown swap for this party!", swap.toJSON()])
            return
        }
        
        info("onSwapSeekerPaid", swap.toJSON())
        emit(event: "swapSeekerPaid", args: [swap])
        
        guard let secretData = try? store.get(.secrets, swap.secretHash), let secret = secretData["secret"] as? Data else {
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
        
        do {
            let party = try awaitPromise(nativeChain.settleInvoice(for: swap.secretHolder, with: swap.secret!))
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
    
    public func deposit(chain: String, symbol: String, amount: BigInt) -> Promise<Liquidity> {
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
            timeoutTimer.schedule(deadline: .now() + 320, repeating: .never)
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
            // Ensure self is available and native chain exists.
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
            timeoutTimer.schedule(deadline: .now() + 60, repeating: .never)
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
    
    // MARK: - Initializer
    
    override init(message: String, code: String, context: [String: Any]? = nil, cause: Error? = nil) {
        super.init(message: message, code: code, context: context, cause: cause)
    }
}
