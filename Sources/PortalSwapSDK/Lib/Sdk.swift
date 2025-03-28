import Foundation
import Combine
import Promises
import BigInt

final class Sdk: BaseClass {
    let accountId: String
    
    private(set) var dex: Dex!
    private(set) var store: Store!
    private(set) var blockchains: Blockchains!
    
    init(config: SwapSdkConfig) {
        accountId = config.id
        
        super.init(id: "sdk")
        
        // Interface to all the blockchain networks
        blockchains = .init(sdk: self, props: config.blockchains)
        
        // Interface to the decentralized exchange
        dex = .init(sdk: self)
        
        // Interface to the underlying data store
        store = .init(accountId: accountId, sdk: self)
        
        // Subscribe for order state changes
        dex.on("swap.completed", forwardEvent("swap.completed"))
        blockchains.on("order.created", forwardEvent("order.created"))
        blockchains.on("swap.created", forwardEvent("swap.created"))
        blockchains.on("swap.validated", forwardEvent("swap.validated"))
        blockchains.on("swap.matched", forwardEvent("swap.matched"))
        
        // Bubble up the log events
        store.on("log", forwardLog())
        dex.on("log", forwardLog())
        blockchains.on("log", forwardLog())
        
        // Bubble up the info events
        store.on("info", forwardLog())
        dex.on("info", forwardLog())
        blockchains.on("info", forwardLog())
        
        // Bubble up the warn events
        store.on("warn", forwardLog())
        dex.on("warn", forwardLog())
        blockchains.on("warn", forwardLog())
        
        // Bubble up the debug events
        store.on("debug", forwardLog())
        dex.on("debug", forwardLog())
        blockchains.on("debug", forwardLog())
        
        // Handling errors
        blockchains.on("error", forwardError())
        store.on("error", forwardError())
        dex.on("error", forwardError())
    }

    func start() -> Promise<Void> {
        debug("starting")

        return all(
            blockchains.connect(),
            store.open()
        ).then { [unowned self] _, _ in
            return info("started")
        }
    }

    func stop() -> Promise<Void> {
        debug("stopping", self)

        return all(
            blockchains.disconnect(),
            store.close(),
            dex.close()
        ).then { [unowned self] _, _, _ in
            return info("stopped")
        }
    }
    
    func listPools() -> Promise<[Pool]> {
        blockchains.listPools()
    }
    
    func priceBtcToEth() -> Promise<BigUInt> {
        blockchains.priceBtcToEth()
    }
    
    func submit(_ order: SwapOrder) -> Promise<Void> {
        dex.submit(order)
    }
    
    func timeoutSwap() {
        dex.timeoutSwap()
    }
    
    func secret(id: String) throws -> String? {
        let secret = try store.get(.secrets, id)
        if let hash = secret["secretHash"] as? String {
            return hash
        } else {
            return nil
        }
    }
}
