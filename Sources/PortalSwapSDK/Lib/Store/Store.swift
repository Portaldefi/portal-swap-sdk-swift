import Foundation
import CoreData
import Promises

class Store: BaseClass {
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
                persistenceManager = try LocalPersistenceManager(
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
        emit(event: "close", args: [])
        return Promise {()}
    }
    
    func get(_ namespace: StoreNamespace, _ key: String) throws -> [String: Any] {
        guard let persistenceManager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }

        let viewContext = persistenceManager.viewContext
        
        switch namespace {
        case .secrets:
            return try DBSecret.entity(key: key, context: viewContext).toJSON()
        case .swaps:
            return try DBSwap.entity(key: key, context: viewContext).toJSON()
        }
    }
    
    func put(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
        guard let persistenceManager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        let viewContext = persistenceManager.viewContext

        switch namespace {
        case .secrets:
            let newEntity = DBSecret(context: viewContext)
            try newEntity.update(json: obj, key: key)
            
            debug("Put secret with ID: \(newEntity.swapID ?? "Unknown")")
        case .swaps:
            let swap = try Swap.from(json: obj).update(sdk: sdk)
            
            let newEntity = DBSwap(context: viewContext)
            try newEntity.update(swap: swap)
            
            debug("Put swap with ID: \(newEntity.swapID ?? "Unknown")")
        }
        
        try viewContext.save()
    }
    
    func update(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
        guard let persistenceManager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        let viewContext = persistenceManager.viewContext
        
        switch namespace {
        case .swaps:
            let swap = try Swap.from(json: obj).update(sdk: sdk)
            let dbSwap = try DBSwap.entity(key: key, context: viewContext)
            try dbSwap.update(swap: swap)
            
            debug("Updating db swap with status: \(dbSwap.status ?? "Unknown")")
        default:
            break
        }
        
        try viewContext.save()
    }
    
    func del(id: String) throws {
        
    }
}
