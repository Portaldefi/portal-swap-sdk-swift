import Foundation
import CoreData

class LocalPersistenceManager: IPersistenceManager {
    
    var viewContext: NSManagedObjectContext { container.viewContext }
    var container: PersistentContainer
    
    required init(configuration: PersistenceConfiguration) throws {
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
}

extension IPersistenceManager {
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
