import Foundation
import CoreData
import Promises

final class Store: BaseClass {
    private let accountId: String
    private var persistenceManager: LocalPersistenceManager?
    
    var isOpen: Bool {
        persistenceManager != nil
    }
    
    init(accountId: String) {
        self.accountId = accountId

        super.init(id: "Store")
    }
    
    func start() async throws {
        persistenceManager = try LocalPersistenceManager.manager(accountId: accountId)
        emit(event: "open", args: [])
    }

    func stop() async throws {
        persistenceManager = nil
        emit(event: "close", args: [])
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
    
    func put(swap: Swap) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
                
        let newEntity = manager.swapEntity()
        try newEntity.update(swap: swap)
        
        debug("Put swap with ID: \(newEntity.swapId?.hexString ?? "Unknown")")
        
        try manager.saveContext()
    }
    
    func get(swapId: String) throws -> Swap {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        let dbSwap = try manager.swap(swapId: swapId)
        return try Swap(record: dbSwap)
    }
    
    func createSecret() throws -> String {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        let (secret, secretHash) = Utils.createSecret()
        let secretEntity = manager.secretEntity()
        secretEntity.data = secret
        secretEntity.secretHash = secretHash.hexString
        
        try manager.saveContext()
        
        return secretHash.hexString
    }
    
    func put(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
//        guard let manager = persistenceManager else {
//            throw SwapSDKError.msg("Cannot obtain persistenceManager")
//        }
//
//        switch namespace {
//        case .secrets:
//            let newEntity = manager.secretEntity()
//            try newEntity.update(json: obj, key: key)
//            
//            debug("Put secret with ID: \(key)")
//        case .swaps:
//            let swap = try AmmSwap.from(json: obj)
//            
//            let newEntity = manager.swapEntity()
//            try newEntity.update(swap: swap)
//            
//            debug("Put swap with ID: \(newEntity.swapId ?? "Unknown")")
//        }
//        
//        try manager.saveContext()
    }
    
    func create(swap: AmmSwap) throws {
//        guard let manager = persistenceManager else {
//            throw SwapSDKError.msg("Cannot obtain persistenceManager")
//        }
//        
//        let newEntity = manager.swapEntity()
//        try newEntity.update(swap: swap)
//        try manager.saveContext()
    }
    
    func update(swap: Swap) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        let dbSwap = try manager.swap(swapId: swap.id)
        try dbSwap.update(swap: swap)
        try manager.saveContext()
    }
    
    func updateBuyAssetTx(id: String, data: String) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        let dbSwap = try manager.swap(key: id)
        dbSwap.buyAssetTx = data
        try manager.saveContext()
    }
    
    func updateSwapStatus(id: String, data: String) throws {
        guard let manager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        let dbSwap = try manager.swap(key: id)
        dbSwap.status = data
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
