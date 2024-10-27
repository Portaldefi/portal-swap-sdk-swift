import Foundation
import Combine
import Promises

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
        subscribe(dex.on("swap.completed", forwardEvent("swap.completed")))
        subscribe(blockchains.on("order.created", forwardEvent("order.created")))
        subscribe(blockchains.on("swap.created", forwardEvent("swap.created")))
        subscribe(blockchains.on("swap.validated", forwardEvent("swap.validated")))
        subscribe(blockchains.on("swap.matched", forwardEvent("swap.matched")))
        
        // Bubble up the log events
        subscribe(store.on("log", forwardLog()))
        subscribe(dex.on("log", forwardLog()))
        subscribe(blockchains.on("log", forwardLog()))
        
        // Bubble up the info events
        subscribe(store.on("info", forwardLog()))
        subscribe(dex.on("info", forwardLog()))
        subscribe(blockchains.on("info", forwardLog()))
        
        // Bubble up the warn events
        subscribe(store.on("warn", forwardLog()))
        subscribe(dex.on("warn", forwardLog()))
        subscribe(blockchains.on("warn", forwardLog()))
        
        // Bubble up the debug events
        subscribe(store.on("debug", forwardLog()))
        subscribe(dex.on("debug", forwardLog()))
        subscribe(blockchains.on("debug", forwardLog()))
        
        // Handling errors
        subscribe(blockchains.on("error", forwardError()))
        subscribe(store.on("error", forwardError()))
        subscribe(dex.on("error", forwardError()))
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
    
    func submit(_ order: SwapOrder) -> Promise<Void> {
        dex.submit(order)
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
