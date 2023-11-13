import Combine
import Foundation
import Promises
import CryptoSwift

public class Swaps: BaseClass {
    private let sdk: Sdk
    private let store: Store
    private var subscriptions = Set<AnyCancellable>()
    
    init(sdk: Sdk, props: [String: Any]) {
        self.sdk = sdk
        self.store = sdk.store

        super.init()
        
        let onSwapAction: ([Any]) -> Void = { [weak self] args in
            if let firstLevel = args as? [[[String: Any]]],
               let secondLevel = firstLevel.first,
               let json = secondLevel.first {
                self?._onSwap(json)
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
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: obj, options: [])
            var swap = try JSONDecoder().decode(Swap.self, from: jsonData)
            
            guard let swapId = swap.id else {
                self.error("swap.error", "Swap has no id")
                return
            }
            
            if swap.isReceived {
                try store.put("swaps", swapId, obj)
            } else {
                let swapObj = try store.get("swaps", swapId)
                let swapData = try JSONSerialization.data(withJSONObject: swapObj, options: [])
                swap = try JSONDecoder().decode(Swap.self, from: swapData)
                try swap.update(obj)
                emit(event: "swap.\(swap.status)", args: [swap])
            }
            
            swap.on("created", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("holder.invoice.created", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("holder.invoice.sent", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("seeker.invoice.created", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("seeker.invoice.sent", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("holder.invoice.paid", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("seeker.invoice.paid", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("holder.invoice.settled", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("seeker.invoice.settled", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)
            swap.on("completed", { [unowned self] _ in self.emit(event: "swap.\(swap.status)", args: [swap]) }).store(in: &subscriptions)

            switch swap.status {
            case "received":
                info("swap.\(swap.status)", [swap])
                emit(event: "swap.\(swap.status)", args: [swap])
                
                if swap.party.isSecretSeeker { return }
                
                var randomBytes = [UInt8](repeating: 0, count: 32)
                _ = randomBytes.withUnsafeMutableBufferPointer { bufferPointer in
                    SecRandomCopyBytes(kSecRandomDefault, 32, bufferPointer.baseAddress!)
                }
                
                let secret = randomBytes
                let secretData = Data(hex: secret.toHexString())
                let secretHash = secretData.sha256().toHexString()
                
                try store.put("secrets", secretHash, [
                    "secret" : secret.toHexString(),
                    "swap": swap.id!
                ])
                
                swap.secretHash = secretHash
            case "created":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])

                try swap.createInvoice()
                try store.put("swaps", swapId, swap.toJSON())
            case "holder.invoice.created":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.sendInvoice()
                try store.put("swaps", swapId, swap.toJSON())
                break
            case "holder.invoice.sent":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.createInvoice()
                try store.put("swaps", swapId, swap.toJSON())
            case "seeker.invoice.created":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.sendInvoice()
                try store.put("swaps", swapId, swap.toJSON())
            case "seeker.invoice.sent":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.payInvoice()
                try store.put("swaps", swapId, swap.toJSON())
                break
            case "holder.invoice.paid":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])

                try swap.payInvoice()
                try store.put("swaps", swapId, swap.toJSON())
                break
            case "seeker.invoice.paid":
                if swap.party.isSecretSeeker { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.settleInvoice()
                try store.put("swaps", swapId, swap.toJSON())
                break
            case "holder.invoice.settled":
                if swap.party.isSecretHolder { return }
                
                info("swap.\(swap.status)", [swap])
                
                try swap.settleInvoice()
                try store.put("swaps", swapId, swap.toJSON())
                break
            case "seeker.invoice.settle", "completed":
                info("swap.\(swap.status)", [swap])

                break
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
