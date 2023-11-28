import Foundation
import Combine
import Promises

public class Sdk: BaseClass {
    public var network: Network!
    public var dex: Dex!
    public var swaps: Swaps!
    public var store: Store!
    public var blockchains: Blockchains!
    
    private var subscriptions = Set<AnyCancellable>()
    
    private lazy var onSwap: ([Any]) -> Void = { [weak self] args in
        if let data = args as? [Swap], let swap = data.first {
            self?.emit(event: "swap.\(swap.status)", args: [swap])
        } else {
            print("Got onSwap with unexpected arguments: \(args) [Sdk]")
        }
    }
    
    private lazy var forwardLogEvent: ([Any]) -> Void = { [weak self] args in
        if let level = args.first as? String, let loggingFunction = self?.getLoggingFunction(for: LogLevel.level(level)) {
            loggingFunction(Array(args.dropFirst()))
        }
    }
    
    public var isConnected: Bool {
        network.isConnected
    }
    
    // Creates a new instance of the Portal SDK
    init(config: SwapSdkConfig) {
        super.init(id: config.id)
        
        // Interface to the underlying network
        self.network = .init(sdk: self, props: config.network)
        
        self.network.on("order.created", forwardEvent(self, event: "order.created")).store(in: &subscriptions)
        self.network.on("order.opened", forwardEvent(self, event: "order.opened")).store(in: &subscriptions)
        self.network.on("order.closed", forwardEvent(self, event: "order.closed")).store(in: &subscriptions)
        
        // Interface to the underlying data store
        self.store = .init()
        
        // Interface to all the blockchain networks
        self.blockchains = .init(sdk: self, props: config.blockchains)
        
        // Interface to the decentralized exchange
        self.dex = .init(sdk: self, props: config.dex)
        
        // Interface to atomic swaps
        self.swaps = .init(sdk: self, props: config.swaps)
        
        self.swaps.on("swap.received", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.created", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.holder.invoice.created", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.holder.invoice.sent", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.seeker.invoice.created", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.seeker.invoice.sent", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.holder.invoice.paid", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.seeker.invoice.paid", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.holder.invoice.settled", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.seeker.invoice.settled", onSwap).store(in: &subscriptions)
        self.swaps.on("swap.completed", onSwap).store(in: &subscriptions)
        
        // Bubble up the log events
        self.network.on("log", forwardLogEvent).store(in: &subscriptions)
        self.store.on("log", forwardLogEvent).store(in: &subscriptions)
        self.blockchains.on("log", forwardLogEvent).store(in: &subscriptions)
        self.dex.on("log", forwardLogEvent).store(in: &subscriptions)
        self.swaps.on("log", forwardLogEvent).store(in: &subscriptions)
    }

    func start() -> Promise<Void> {
        debug("starting", self)

        return Promise { [unowned self] resolve, reject in
            all(
                self.network.connect(),
                self.store.open(),
                self.blockchains.connect(),
                self.dex.open()
            ).then { network, store, blockchains, dex in
                self.info("start", self)
                self.emit(event: "start")
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
                self.network.disconnect(),
                self.store.close(),
                self.blockchains.disconnect(),
                self.dex.close()
            ).then { network, store, blockchains, dex in
                self.info("stop", self)
                self.emit(event: "stop")
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
}

extension Sdk {
    private func forwardEvent(_ self: BaseClass, event: String) -> ([Any]) -> Void {
        return { args in
            self.emit(event: event, args: args)
        }
    }
    
    private func getLoggingFunction(for level: LogLevel) -> ([Any]) -> Void {
        switch level {
        case .debug:
            return { args in
                print("SWAP SDK DEBUG:", args)
            }
        case .info:
            return { args in
                print("SWAP SDK INFO:", args)
            }
        case .warn:
            return { args in
                print("SWAP SDK WARN:", args)
            }
        case .error:
            return { args in
                print("SWAP SDK ERROR:", args)
            }
        case .unknown:
            return { args in
                print("SWAP SDK Unknown:", args)
            }
        }
    }
}
