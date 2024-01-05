import Combine
import Foundation
import Promises

class Swaps: BaseClass {
    private let sdk: Sdk
    private let store: Store
    private let onSwapAccessQueue = DispatchQueue(label: "swap.sdk.onSwapAccessQueue")
    private var subscriptions = Set<AnyCancellable>()
    
    private lazy var onError: ([Any]) -> Void = { [unowned self] args in
        emit(event: "error", args: args)
    }
    
    private lazy var onSwapAction: ([Any]) -> Void = { [unowned self] args in
        if let firstLevel = args as? [[[String: Any]]],
           let secondLevel = firstLevel.first,
           let json = secondLevel.first {
            onSwapAccessQueue.async {
                self._onSwap(json)
            }
        } else {
            debug("Cannot handle onSwap action")
        }
    }
    
    init(sdk: Sdk, props: [String: Any]) {
        self.sdk = sdk
        self.store = sdk.store

        super.init()
        
        sdk.network.on("swap.received", onSwapAction).store(in: &subscriptions)
        sdk.network.on("swap.holder.invoice.sent", onSwapAction).store(in: &subscriptions)
        sdk.network.on("swap.seeker.invoice.sent", onSwapAction).store(in: &subscriptions)
        sdk.network.on("error", onError).store(in: &subscriptions)
    }
    
    func sync() -> Promise<Swaps> {
        // TODO: Fix this to load from the store on startup
        // TODO: Fix this to write to the store on shutdown
        Promise {
            self
        }
    }
    // Function call on swap status update.
    // SH: receive -> create -> holder.invoice.created -> holder.invoice.sent -> seeker.invoice.sent -> seeker.invoice.paid -> holder.invoice.settled -> completed
    // SS: receive -> holder.invoice.sent -> seeker.invoice.created -> seeker.invoice.sent -> holder.invoice.paid -> seeker.invoice.settled -> completed
    func _onSwap(_ obj: [String: Any]) {
        subscriptions.removeAll()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: obj, options: [])
            let swap = try JSONDecoder().decode(Swap.self, from: jsonData)
            swap.update(sdk: sdk)
                        
            guard let swapId = swap.id else {
                self.error("swap.error", "Swap has no id")
                return
            }
            
            debug("\(swap.party.id) Received swap with status: \(swap.status)")
            
            if swap.isReceived {
                try store.put(.swaps, swapId, obj)
            } else {
                try store.update(.swaps, swapId, obj)
                emit(event: "swap.\(swap.status)", args: [swap])
            }
            
            subscribeForSwapStateChanges(swap: swap)

            switch swap.status {
            case "received":
                info("swap.\(swap.status)", [swap])
                emit(event: "swap.\(swap.status)", args: [swap])
                
                if swap.party.isSecretSeeker { return }
                
                let secret = Utils.createSecret()
                let secretHash = Utils.sha256(data: secret)
                let secretHashString = secretHash.toHexString()
                                
                debug("SWAP SDK created secret: \(secretHashString)")
                
                try store.put(.secrets, secretHashString, [
                    "secret" : secret.toHexString(),
                    "swap": swap.id!
                ])
                
                swap.secretHash = secretHashString
                
                _onSwap(swap.toJSON())
            case "created":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])

                swap.createInvoice().then { [unowned self] _ in
                    self._onSwap(swap.toJSON())
                }.catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.created":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.sendInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.sent":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                swap.createInvoice().then { [unowned self] _ in
                    self._onSwap(swap.toJSON())
                }.catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "seeker.invoice.created":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.sendInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "seeker.invoice.sent":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                swap.payInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.paid":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])

                swap.payInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "seeker.invoice.paid":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                swap.counterparty.swap = swap
                
                swap.settleInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.settled":
                if swap.party.isSecretSeeker {
                    info("swap.\(swap.status)", [swap])
                    
                    swap.settleInvoice().catch { error in
                        self.error("swap.error", error)
                        self.emit(event: "error", args: [error, obj])
                    }
                }
                
                if swap.party.isSecretHolder {
                    swap.status = "completed"
                    
                    info("swap.\(swap.status)", [swap])
                    self._onSwap(swap.toJSON())
                }
            case "seeker.invoice.settled":
                swap.status = "completed"
                
                info("swap.\(swap.status)", [swap])
                self._onSwap(swap.toJSON())
            case "completed":
                info("swap.\(swap.status)", [swap])
                emit(event: "swap.\(swap.status)", args: [swap])
            default:
                let error = SwapSDKError.msg("unknown status \(swap.status)")
                self.error("swap.error", error)
            }
        } catch {
            self.error("swap.error", error)
            self.emit(event: "error", args: [error, obj])
        }
    }
    
    private func subscribeForSwapStateChanges(swap: Swap) {
        swap.on("log", { args in
            if let level = args.first as? String {
                switch LogLevel.level(level) {
                case .debug:
                    print("SWAP SDK DEBUG:", args)
                case .info:
                    print("SWAP SDK INFO:", args)
                case .warn:
                    print("SWAP SDK WARN:", args)
                case .error:
                    print("SWAP SDK ERROR:", args)
                case .unknown:
                    break
                }
            }
        })
        .store(in: &subscriptions)
        
        swap.on("created", { [unowned self] _ in
            self.emit(event: "swap.\(swap.status)", args: [swap])
        })
        .store(in: &subscriptions)
        
        swap.on("holder.invoice.created", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
        })
        .store(in: &subscriptions)
        
        swap.on("holder.invoice.sent", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
        })
        .store(in: &subscriptions)
        
        swap.on("seeker.invoice.created", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
        })
        .store(in: &subscriptions)
        
        swap.on("seeker.invoice.sent", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
        })
        .store(in: &subscriptions)
        
        swap.on("holder.invoice.paid", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
            
            onSwapAccessQueue.async {
                self._onSwap(swap.toJSON())
            }
        })
        .store(in: &subscriptions)
        
        swap.on("seeker.invoice.paid", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
            
            onSwapAccessQueue.async {
                self._onSwap(swap.toJSON())
            }
        })
        .store(in: &subscriptions)
        
        swap.on("holder.invoice.settled", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
            
            onSwapAccessQueue.async {
                self._onSwap(swap.toJSON())
            }
        })
        .store(in: &subscriptions)
        
        swap.on("seeker.invoice.settled", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
            
            onSwapAccessQueue.async {
                self._onSwap(swap.toJSON())
            }
        })
        .store(in: &subscriptions)
        
        swap.on("completed", { [unowned self] _ in
            emit(event: "swap.\(swap.status)", args: [swap])
        })
        .store(in: &subscriptions)
    }
}
