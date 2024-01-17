import Combine
import Foundation
import Promises

public final class SDK: BaseClass {
    private let sdk: Sdk

    public var isConnected: Bool {
        sdk.network.isConnected
    }
    
    public init(config: SwapSdkConfig) {
        sdk = .init(config: config)
        
        super.init(id: "SDK")
        
        subscribe(sdk.on("order.created", forwardEvent("order.created")))
        subscribe(sdk.on("order.opened", forwardEvent("order.opened")))
        subscribe(sdk.on("order.closed", forwardEvent("order.closed")))
        
        subscribe(sdk.on("swap.received", forwardSwap()))
        subscribe(sdk.on("swap.holder.invoice.created", forwardSwap()))
        subscribe(sdk.on("swap.holder.invoice.sent", forwardSwap()))
        subscribe(sdk.on("swap.seeker.invoice.created", forwardSwap()))
        subscribe(sdk.on("swap.seeker.invoice.sent", forwardSwap()))
        subscribe(sdk.on("swap.holder.invoice.paid", forwardSwap()))
        subscribe(sdk.on("swap.seeker.invoice.paid", forwardSwap()))
        subscribe(sdk.on("swap.holder.invoice.settled", forwardSwap()))
        subscribe(sdk.on("swap.seeker.invoice.settled", forwardSwap()))
        subscribe(sdk.on("swap.completed", forwardSwap()))
        
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
    
    public func submitLimitOrder(_ request: OrderRequest) -> Promise<Order> {
        sdk.dex.submitLimitOrder(request)
    }
    
    public func cancelLimitOrder(_ order: Order) -> Promise<Order> {
        sdk.dex.cancelLimitOrder(order)
    }
}
