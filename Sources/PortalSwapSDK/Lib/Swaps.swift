import Combine
import Foundation
import Promises

final class Swaps: BaseClass {
    private let sdk: Sdk
    private let store: Store
    private let onSwapAccessQueue = DispatchQueue(label: "swap.sdk.onSwapAccessQueue")
    
    init(sdk: Sdk) {
        self.sdk = sdk
        store = sdk.store

        super.init(id: "Swaps")
        
        subscribe(sdk.network.on("swap.received", onSwapUpdate()))
        subscribe(sdk.network.on("swap.holder.invoice.sent", onSwapUpdate()))
        subscribe(sdk.network.on("swap.seeker.invoice.sent", onSwapUpdate()))
        subscribe(sdk.network.on("error", forwardError()))
    }
    
    func sync() -> Promise<Swaps> {
        // TODO: Fix this to load from the store on startup
        // TODO: Fix this to write to the store on shutdown
        Promise {
            self
        }
    }
    // Function call on swap status update.
    // SH: received -> created -> holder.invoice.created -> holder.invoice.sent -> seeker.invoice.sent -> seeker.invoice.paid -> holder.invoice.settled -> completed
    // SS: received -> holder.invoice.sent -> seeker.invoice.created -> seeker.invoice.sent -> holder.invoice.paid -> seeker.invoice.settled -> completed
    func _onSwap(_ obj: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: obj, options: [])
            let swap = try JSONDecoder().decode(Swap.self, from: jsonData).update(sdk: sdk)
            
            debug("Party \(swap.party.id) received swap with status: \(swap.status)")
            
            if swap.isReceived {
                try store.put(.swaps, swap.swapId, obj)
            } else {
                try store.update(.swaps, swap.swapId, obj)
                emit(event: "swap.\(swap.status)", args: [swap])
            }
            
            subscribeForSwapStateChanges(swap: swap)

            switch swap.status {
            case "received":
                info("swap.\(swap.status)", swap.toJSON())
                emit(event: "swap.\(swap.status)", args: [swap])
                
                if swap.partyType == .secretSeeker { return }
                
                let secret = Utils.createSecret()
                let secretHash = Utils.sha256(data: secret)
                let secretHashString = secretHash.toHexString()
                                
                debug("Created secret: \(secretHashString)")
                
                try store.put(.secrets, secretHashString, [
                    "secret" : secret.toHexString(),
                    "swap": swap.swapId
                ])
                
                swap.secretHash = secretHashString
                
                _onSwap(swap.toJSON())
            case "created":
                if swap.partyType == .secretSeeker { return }
                
                info("swap.\(swap.status)", swap.toJSON())

                swap.createInvoice().then { [unowned self] _ in
                    _onSwap(swap.toJSON())
                }.catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.created":
                if swap.partyType == .secretSeeker { return }
                
                info("swap.\(swap.status)", swap.toJSON())
                
                try swap.sendInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.sent":
                if swap.partyType == .secretHolder { return }
                
                info("swap.\(swap.status)", swap.toJSON())
                
                swap.createInvoice().then { [unowned self] _ in
                    self._onSwap(swap.toJSON())
                }.catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "seeker.invoice.created":
                if swap.partyType == .secretHolder { return }

                info("swap.\(swap.status)", swap.toJSON())
                
                try swap.sendInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "seeker.invoice.sent":
                if swap.partyType == .secretSeeker { return }

                info("swap.\(swap.status)", swap.toJSON())
                
                swap.payInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.paid":
                if swap.partyType == .secretHolder { return }

                info("swap.\(swap.status)", swap.toJSON())

                swap.payInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "seeker.invoice.paid":
                if swap.partyType == .secretSeeker { return }

                info("swap.\(swap.status)", swap.toJSON())
                
                swap.counterparty.update(swap: swap)
                
                swap.settleInvoice().catch { error in
                    self.error("swap.error", error)
                    self.emit(event: "error", args: [error, obj])
                }
            case "holder.invoice.settled":
                if swap.partyType == .secretSeeker {
                    info("swap.\(swap.status)", swap.toJSON())
                    
                    swap.settleInvoice().catch { error in
                        self.error("swap.error", error)
                        self.emit(event: "error", args: [error, obj])
                    }
                }
                
                if swap.partyType == .secretHolder {
                    swap.status = "completed"
                    
                    info("swap.\(swap.status)", swap.toJSON())
                    self._onSwap(swap.toJSON())
                }
            case "seeker.invoice.settled":
                swap.status = "completed"
                
                info("swap.\(swap.status)", swap.toJSON())
                self._onSwap(swap.toJSON())
            case "completed":
                info("swap.\(swap.status)", swap.toJSON())
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
}

extension Swaps {
    private func onSwapUpdate() -> ([Any]) -> Void {
        { [unowned self] args in
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
    }
    
    private func subscribeForSwapStateChanges(swap: Swap) {
        subscribe(
            swap.on("created", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
            })
        )
        
        subscribe(
            swap.on("holder.invoice.created", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
            })
        )
        
        subscribe(
            swap.on("holder.invoice.sent", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
            })
        )
        
        subscribe(
            swap.on("seeker.invoice.created", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
            })
        )
        
        subscribe(
            swap.on("seeker.invoice.sent", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
            })
        )
        
        subscribe(
            swap.on("holder.invoice.paid", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
                
                onSwapAccessQueue.async {
                    self._onSwap(swap.toJSON())
                }
            })
        )
        
        subscribe(
            swap.on("seeker.invoice.paid", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
                
                onSwapAccessQueue.async {
                    self._onSwap(swap.toJSON())
                }
            })
        )
        
        subscribe(
            swap.on("holder.invoice.settled", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
                
                onSwapAccessQueue.async {
                    self._onSwap(swap.toJSON())
                }
            })
        )
        
        subscribe(
            swap.on("seeker.invoice.settled", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
                
                onSwapAccessQueue.async {
                    self._onSwap(swap.toJSON())
                }
            })
        )
        
        subscribe(
            swap.on("completed", { [unowned self] _ in
                emit(event: "swap.\(swap.status)", args: [swap])
            })
        )
    }
}
