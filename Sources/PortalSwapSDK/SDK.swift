import Combine
import Foundation
import Promises

public final class SDK: BaseClass {
    private let sdk: Sdk
    
    public init(config: SwapSdkConfig) {
        sdk = .init(config: config)
        
        super.init(id: "SDK")
        
        subscribe(sdk.on("order.created", forwardEvent("order.created")))
        subscribe(sdk.on("order.opened", forwardEvent("order.opened")))
        subscribe(sdk.on("order.closed", forwardEvent("order.closed")))
        
        subscribe(sdk.on("swap.completed", forwardEvent("swap.completed")))
        subscribe(sdk.on("notary.validator.match.order", forwardEvent("notary.validator.match.order")))
        
        subscribe(sdk.on("log", forwardLog()))
        subscribe(sdk.on("error", forwardError()))
        
        debug("SWAP SDK init \(config.id)")
    }
    
    public func start() -> Promise<Void> {
        sdk.start()
    }
    
    public func stop() -> Promise<Void> {
        sdk.stop()
    }
    
    public func listPools() -> Promise<[Pool]> {
        sdk.listPools()
    }
    
    public func submit(_ order: SwapOrder) -> Promise<[String: String]> {
        sdk.submit(order)
    }
}
