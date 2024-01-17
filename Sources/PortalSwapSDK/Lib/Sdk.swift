import Foundation
import Combine
import Promises

class Sdk: BaseClass {
    let userId: String
    
    private(set) var network: Network!
    private(set) var dex: Dex!
    private(set) var store: Store!
    private(set) var blockchains: Blockchains!
    private(set) var swaps: Swaps!
            
    public var isConnected: Bool {
        network.isConnected
    }
    
    // Creates a new instance of Portal SDK
    init(config: SwapSdkConfig) {
        userId = config.id
        
        super.init(id: "Sdk")
        
        // Interface to the underlying network
        network = .init(sdk: self, props: config.network)
        
        // Interface to all the blockchain networks
        blockchains = .init(sdk: self, props: config.blockchains)
        
        // Interface to the decentralized exchange
        dex = .init(sdk: self)
        
        // Interface to the underlying data store
        store = .init(sdk: self)
        
        // Interface to atomic swaps
        swaps = .init(sdk: self)
        
        // Subscribe for order state changes
        subscribe(network.on("order.created", forwardEvent("order.created")))
        subscribe(network.on("order.created", forwardEvent("order.created")))
        subscribe(network.on("order.opened", forwardEvent("order.opened")))
        subscribe(network.on("order.closed", forwardEvent("order.closed")))
        
        // Subscribe for swap state changes
        subscribe(swaps.on("swap.received", forwardSwap()))
        subscribe(swaps.on("swap.created", forwardSwap()))
        subscribe(swaps.on("swap.holder.invoice.created", forwardSwap()))
        subscribe(swaps.on("swap.holder.invoice.sent", forwardSwap()))
        subscribe(swaps.on("swap.seeker.invoice.created", forwardSwap()))
        subscribe(swaps.on("swap.seeker.invoice.sent", forwardSwap()))
        subscribe(swaps.on("swap.holder.invoice.paid", forwardSwap()))
        subscribe(swaps.on("swap.seeker.invoice.paid", forwardSwap()))
        subscribe(swaps.on("swap.holder.invoice.settled", forwardSwap()))
        subscribe(swaps.on("swap.seeker.invoice.settled", forwardSwap()))
        subscribe(swaps.on("swap.completed", forwardSwap()))
        
        // Bubble up the log events
        subscribe(network.on("log", forwardLog()))
        subscribe(store.on("log", forwardLog()))
        subscribe(blockchains.on("log", forwardLog()))
        subscribe(dex.on("log", forwardLog()))
        subscribe(swaps.on("log", forwardLog()))
        
        // Handling errors
        subscribe(blockchains.on("error", forwardError()))
        subscribe(swaps.on("error", forwardError()))
    }

    func start() -> Promise<Void> {
        debug("starting")

        return Promise { [unowned self] resolve, reject in
            all(
                network.connect(),
                blockchains.connect(),
                store.open(),
                dex.open()
            ).then { [unowned self] network, blockchains, store, dex in
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
