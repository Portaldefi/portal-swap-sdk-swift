import Foundation
import CoreData

public final class LocalPersistenceManager {
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
    
    internal func swapEntity() -> DBSwap {
        DBSwap(context: viewContext)
    }
    
    internal func swap(key: String) throws -> DBSwap {
        try DBSwap.entity(key: key, context: viewContext)
    }
    
    public func fetchSwaps() throws -> [SwapModel] {
        try DBSwap.entities(context: viewContext).compactMap{ try? SwapModel(record: $0) }
    }
}

extension LocalPersistenceManager {
    static public func manager() throws -> LocalPersistenceManager {
        let config: PersistenceConfiguration = .init(
            modelName: "DBModel",
            cloudIdentifier: String(),
            configuration: "Local"
        )
        return try LocalPersistenceManager(configuration: config)
    }
    
    static func manager(configuration: PersistenceConfiguration) throws -> LocalPersistenceManager {
        return try LocalPersistenceManager(configuration: configuration)
    }
    
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
