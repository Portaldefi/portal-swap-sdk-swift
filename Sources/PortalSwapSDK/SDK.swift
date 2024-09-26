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
        
        subscribe(sdk.on("swap.created", forwardEvent("swap.created")))
        subscribe(sdk.on("swap.validated", forwardEvent("swap.validated")))
        subscribe(sdk.on("swap.matched", forwardEvent("swap.matched")))
        subscribe(sdk.on("swap.completed", forwardEvent("swap.completed")))
        
        subscribe(sdk.on("log", forwardLog()))
        subscribe(sdk.on("info", forwardLog()))
        subscribe(sdk.on("debug", forwardLog()))
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
    
    public func submit(_ order: SwapOrder) -> Promise<Void> {
        sdk.submit(order)
    }
    
    public func secret(id: String) throws -> String? {
        try sdk.secret(id: id)
    }

}
