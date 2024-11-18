import Foundation
import CoreData
import Promises

final class Store: BaseClass {
    private let accountId: String
    private let sdk: Sdk
    private var persistenceManager: LocalPersistenceManager?
    
    var isOpen: Bool {
        persistenceManager != nil
    }
    
    init(accountId: String, sdk: Sdk) {
        self.accountId = accountId
        self.sdk = sdk
        
        super.init(id: "Store")
    }
    
    func open() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                persistenceManager = try LocalPersistenceManager.manager(accountId: accountId)
                
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
            let swap = try AmmSwap.from(json: obj)
            
            let newEntity = manager.swapEntity()
            try newEntity.update(swap: swap)
            
            debug("Put swap with ID: \(newEntity.swapId ?? "Unknown")")
        }
        
        try manager.saveContext()
    }
    
    func create(swap: AmmSwap) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        let newEntity = manager.swapEntity()
        try newEntity.update(swap: swap)
    }
    
    func updateBuyAssetTx(id: String, data: String) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        let dbSwap = try manager.swap(key: id)
        dbSwap.buyAssetTx = data
        try manager.saveContext()
    }
    
    func updateSellAssetTx(id: String, data: String) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        let dbSwap = try manager.swap(key: id)
        dbSwap.sellAssetTx = data
        try manager.saveContext()
    }
    
    func del(id: String) throws {
        
    }
}
