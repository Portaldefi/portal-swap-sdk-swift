import Foundation
import Combine
import Promises

final class Sdk: BaseClass {
    let userId: String
    
    private(set) var dex: Dex!
    private(set) var store: Store!
    private(set) var blockchains: Blockchains!
    private(set) var assetManagement: AssetManagement!
    
    // Creates a new instance of Portal SDK
    init(config: SwapSdkConfig) {
        userId = config.id
        
        super.init(id: "sdk")
        
        // Interface to the underlying network
        assetManagement = .init(props: config.blockchains.portal)
        
        // Interface to all the blockchain networks
        blockchains = .init(sdk: self, props: config.blockchains)
        
        // Interface to the decentralized exchange
        dex = .init(sdk: self)
        
        // Interface to the underlying data store
        store = .init(sdk: self)
        
        // Subscribe for order state changes
        subscribe(dex.on("swap.completed", forwardEvent("swap.completed")))
        subscribe(blockchains.on("notary.validator.match.order", forwardEvent("notary.validator.match.order")))
        
        // Bubble up the log events
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
                blockchains.disconnect(),
                store.close(),
                dex.close()
            ).then { [unowned self] blockchains, store, dex in
                info("stopped")
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
    
    func assetPairs() -> Promise<[AssetPair]> {
        assetManagement.assetPairs()
    }
}
