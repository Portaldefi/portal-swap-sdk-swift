import Combine
import Foundation
import Promises

public class SDK: BaseClass {
    private let sdk: Sdk!
    
    private var subscriptions = Set<AnyCancellable>()

    public var isConnected: Bool {
        sdk.network.isConnected
    }
    
    private lazy var onSwap: ([Any]) -> Void = { [weak self] args in
        if let data = args as? [Swap], let swap = data.first {
            self?.emit(event: "swap.\(swap.status)", args: [swap])
        } else {
            print("Got onSwap with unexpected arguments: \(args) [SDK]")
        }
    }
    
    public init(config: SwapSdkConfig) {
        sdk = .init(config: config)
        
        super.init()
        
        sdk.on("order.created", { [unowned self] args in emit(event: "order.created", args: args) }).store(in: &subscriptions)
        sdk.on("order.opened", { [unowned self] args in emit(event: "order.opened", args: args) }).store(in: &subscriptions)
        sdk.on("order.closed", { [unowned self] args in emit(event: "order.closed", args: args) }).store(in: &subscriptions)
        sdk.on("swap.holder.invoice.created", onSwap).store(in: &subscriptions)
        sdk.on("swap.holder.invoice.sent", onSwap).store(in: &subscriptions)
        sdk.on("swap.seeker.invoice.created", onSwap).store(in: &subscriptions)
        sdk.on("swap.seeker.invoice.sent", onSwap).store(in: &subscriptions)
        sdk.on("swap.holder.invoice.paid", onSwap).store(in: &subscriptions)
        sdk.on("swap.seeker.invoice.paid", onSwap).store(in: &subscriptions)
        sdk.on("swap.holder.invoice.settled", onSwap).store(in: &subscriptions)
        sdk.on("swap.seeker.invoice.settled", onSwap).store(in: &subscriptions)
        sdk.on("swap.completed", onSwap).store(in: &subscriptions)
        sdk.on("message", { [unowned self] args in emit(event: "message", args: args) }).store(in: &subscriptions)
        sdk.on("log", { [unowned self] args in emit(event: "log", args: args) }).store(in: &subscriptions)
        
        print("SWAP SDK init \(config.id)")
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
