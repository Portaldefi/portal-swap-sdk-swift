import Foundation
import CoreData
import Promises

final class Store: BaseClass {
    private let sdk: Sdk
    private var persistenceManager: LocalPersistenceManager?
    
    var isOpen: Bool {
        persistenceManager != nil
    }
    
    init(sdk: Sdk) {
        self.sdk = sdk
        
        super.init(id: "Store")
    }
    
    func open() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                persistenceManager = try LocalPersistenceManager.manager(
                    configuration: .init(
                        modelName: "DBModel",
                        cloudIdentifier: String(),
                        configuration: "Local"
                    )
                )
                
                emit(event: "open", args: [])
                
                resolve(())
            } catch {
               reject(error)
            }
        }
    }

    func close() -> Promise<Void> {
        persistenceManager = nil
        emit(event: "close", args: [])
        return Promise {()}
    }
    
    func get(_ namespace: StoreNamespace, _ key: String) throws -> [String: Any] {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        switch namespace {
        case .secrets:
            return try manager.secret(key: key).toJSON()
        case .swaps:
            return try manager.swap(key: key).toJSON()
        }
    }
    
    func getAmmSwap(key: String) throws -> AmmSwap {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        return AmmSwap(record: try manager.swap(key: key))
    }
    
    func put(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }

        switch namespace {
        case .secrets:
            let newEntity = manager.secretEntity()
            try newEntity.update(json: obj, key: key)
            
            debug("Put secret with ID: \(key)")
        case .swaps:
            let swap = try AmmSwap.from(json: obj)//.update(sdk: sdk)
            
            let newEntity = manager.swapEntity()
            try newEntity.update(swap: swap)
            
            debug("Put swap with ID: \(newEntity.swapId ?? "Unknown")")
        }
        
        try manager.saveContext()
    }
    
    func update(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
                
        switch namespace {
        case .swaps:
            let swap = try AmmSwap.from(json: obj)//.update(sdk: sdk)
            let dbSwap = try manager.swap(key: key)
            try dbSwap.update(swap: swap)
            
            debug("Updating db swap with status: \(dbSwap.status ?? "Unknown")")
        default:
            break
        }
        
        try manager.saveContext()
    }
    
    func del(id: String) throws {
        
    }
}
