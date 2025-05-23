import Foundation
import CoreData

public final class LocalPersistenceManager {
    private let configuration: PersistenceConfiguration
    private var viewContext: NSManagedObjectContext { container.viewContext }
    private var container: PersistentContainer
    
    fileprivate init(configuration: PersistenceConfiguration) throws {
        let model = try LocalPersistenceManager.model(for: configuration.modelName)
        
        container = .init(name: configuration.modelName, managedObjectModel: model)
        container.loadPersistentStores(completionHandler: { (desc, err) in
            if let err = err {
                print("Error loading LOCAL STORE: \(desc): \(err)")
                return
            }
            print("Loaded LOCAL STORE successfully")
        })
        
        self.configuration = configuration
    }
    
    internal func saveContext() throws {
        try viewContext.save()
    }
    
    internal func secretEntity() -> DBSecret {
        DBSecret(context: viewContext)
    }
    
    internal func secret(key: String) throws -> DBSecret {
        try DBSecret.entity(key: key, context: viewContext)
    }
    
    internal func swapEntity() -> DBAmmSwap {
        let swap = DBAmmSwap(context: viewContext)
        swap.accountId = configuration.accountId
        return swap
    }
    
    internal func swap(key: String) throws -> DBAmmSwap {
        try DBAmmSwap.entity(key: key, context: viewContext)
    }
    
    public func fetchSwaps() throws -> [AmmSwap] {
        let swaps = try DBAmmSwap.entities(context: viewContext)
            .filter { $0.accountId == configuration.accountId }
            .map { AmmSwap(record: $0) }

        return Array(Set(swaps))
    }
    
    public func fetchSecret(key: String) throws -> Data? {
        (try DBSecret.entity(key: key, context: viewContext)).data
    }
}

extension LocalPersistenceManager {
    static public func manager(accountId: String) throws -> LocalPersistenceManager {
        let config: PersistenceConfiguration = .init(
            accountId: accountId,
            modelName: "DBModel",
            cloudIdentifier: String(),
            configuration: "Local"
        )
        return try LocalPersistenceManager(configuration: config)
    }
    
//    static func manager(configuration: PersistenceConfiguration) throws -> LocalPersistenceManager {
//        return try LocalPersistenceManager(configuration: configuration)
//    }
    
    static func model(for name: String) throws -> NSManagedObjectModel {
        guard let url = Bundle.module.url(forResource: name, withExtension: "momd") else {
            throw SwapSDKError.msg("Could not get URL for model: \(name)")
        }
        
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            throw SwapSDKError.msg("Could not get model for: \(url)")
        }
        
        return model
    }
}
