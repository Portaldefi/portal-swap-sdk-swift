import Combine
import Foundation
import Promises

public class Swaps: BaseClass {
    private let sdk: Sdk
    private let store: Store
    private let onSwapAccessQueue = DispatchQueue(label: "swap.sdk.onSwapAccessQueue")
    private var subscriptions = Set<AnyCancellable>()
    
    init(sdk: Sdk, props: [String: Any]) {
        self.sdk = sdk
        self.store = sdk.store

        super.init()
        
        let onSwapAction: ([Any]) -> Void = { [weak self] args in
            if let firstLevel = args as? [[[String: Any]]],
               let secondLevel = firstLevel.first,
               let json = secondLevel.first {
                self?.onSwapAccessQueue.async {
                    self?._onSwap(json)
                }
            } else {
                print("Cannot handle onSwap action")
            }
        }
        
        sdk.network.on("swap.received", onSwapAction).store(in: &subscriptions)
        sdk.network.on("swap.holder.invoice.sent", onSwapAction).store(in: &subscriptions)
        sdk.network.on("swap.seeker.invoice.sent", onSwapAction).store(in: &subscriptions)
    }
    
    func sync() -> Promise<Swaps> {
        // TODO: Fix this to load from the store on startup
        // TODO: Fix this to write to the store on shutdown
        Promise {
            self
        }
    }
    
    func _onSwap(_ obj: [String: Any]) {
        subscriptions.removeAll()
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: obj, options: [])
            var swap = try JSONDecoder().decode(Swap.self, from: jsonData)
            swap.sdk = sdk
                        
            guard let swapId = swap.id else {
                self.error("swap.error", "Swap has no id")
                return
            }
            
            print("\(swap.party.id) Received swap with status: \(swap.status)")
            
            if swap.isReceived {
                try store.put("swaps", swapId, obj)
            } else {
//                let swapObj = try store.get("swaps", swapId)
//                let swapData = try JSONSerialization.data(withJSONObject: swapObj, options: [])
//                swap = try JSONDecoder().decode(Swap.self, from: swapData)
//                try swap.update(obj)
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
                                
                print("SWAP SDK created secret: \(secretHashString)")
                
                try store.put("secrets", secretHashString, [
                    "secret" : secret.toHexString(),
                    "swap": swap.id!
                ])
                
                swap.secretHash = secretHashString
                
                _onSwap(swap.toJSON())
            case "created":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])

                swap.createInvoice().then { [unowned self] _ in
                    try self.store.put("swaps", swapId, swap.toJSON())
                }.then { [unowned self] _ in
                    self._onSwap(swap.toJSON())
                }
            case "holder.invoice.created":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                _ = try swap.sendInvoice()
                try self.store.put("swaps", swapId, swap.toJSON())
            case "holder.invoice.sent":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                swap.createInvoice().then { _ in
                    try self.store.put("swaps", swapId, swap.toJSON())
                }
                .then { [unowned self] _ in
                    self._onSwap(swap.toJSON())
                }
            case "seeker.invoice.created":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                _ = try swap.sendInvoice()
                try self.store.put("swaps", swapId, swap.toJSON())
            case "seeker.invoice.sent":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                _ = swap.payInvoice()
                try self.store.put("swaps", swapId, swap.toJSON())
            case "holder.invoice.paid":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])

                _ = swap.payInvoice()
                try store.put("swaps", swapId, swap.toJSON())
            case "seeker.invoice.paid":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                swap.counterparty.swap = swap
                
                _ = swap.settleInvoice()
                try self.store.put("swaps", swapId, swap.toJSON())
            case "holder.invoice.settled":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                _ = swap.settleInvoice()
                try store.put("swaps", swapId, swap.toJSON())
            case "seeker.invoice.settled":
                if swap.party.isSecretHolder { return }

                swap.status = "completed"
                
                info("swap.\(swap.status)", [swap])
                try store.put("swaps", swapId, swap.toJSON())
                emit(event: swap.status)
            case "completed":
                info("swap.\(swap.status)", [swap])
                try store.put("swaps", swapId, swap.toJSON())
                emit(event: swap.status)
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
