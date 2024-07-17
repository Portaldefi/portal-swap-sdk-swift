import Foundation
import Combine
import Promises

final class Sdk: BaseClass {
    let userId: String
    
    private(set) var network: Network!
    private(set) var dex: Dex!
    private(set) var store: Store!
    private(set) var blockchains: Blockchains!
            
    public var isConnected: Bool {
        network.isConnected
    }
    
    // Creates a new instance of Portal SDK
    init(config: SwapSdkConfig) {
        userId = config.id
        
        super.init(id: "sdk")
        
        // Interface to the underlying network
        network = .init(sdk: self, props: config.network)
        
        // Interface to all the blockchain networks
        blockchains = .init(sdk: self, props: config.blockchains)
        
        // Interface to the decentralized exchange
        dex = .init(sdk: self)
        
        // Interface to the underlying data store
        store = .init(sdk: self)
        
        // Subscribe for order state changes
        subscribe(network.on("order.created", forwardEvent("order.created")))
        subscribe(network.on("order.created", forwardEvent("order.created")))
        subscribe(network.on("order.opened", forwardEvent("order.opened")))
        subscribe(network.on("order.closed", forwardEvent("order.closed")))
        
        subscribe(dex.on("swap.completed", forwardEvent("swap.completed")))
        subscribe(blockchains.on("notary.validator.match.intent", forwardEvent("notary.validator.match.intent")))
        
        // Bubble up the log events
        subscribe(network.on("log", forwardLog()))
        subscribe(store.on("log", forwardLog()))
        subscribe(dex.on("log", forwardLog()))
        subscribe(blockchains.on("log", forwardLog()))
        
        // Handling errors
        subscribe(blockchains.on("error", forwardError()))
    }

    func start() -> Promise<Void> {
        debug("starting")

        return Promise { [unowned self] resolve, reject in
            all(
//                network.connect(),
                blockchains.connect(),
                store.open()
//                dex.open()
            ).then { [unowned self] blockchains, store in
                info("started")
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }

    func stop() -> Promise<Void> {
        debug("stopping", self)

        return Promise { [unowned self] resolve, reject in
            all(
                network.disconnect(),
                blockchains.disconnect(),
                store.close(),
                dex.close()
            ).then { [unowned self] network, blockchains, store, dex in
                info("stopped")
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
}
