import Foundation
import CoreData

class LocalPersistenceManager: IPersistenceManager {
    
    var viewContext: NSManagedObjectContext { container.viewContext }
    var container: PersistentContainer
    
    required init(
        configuration: PersistenceConfiguration
    ) throws {
    
        let model = try LocalPersistenceManager.model(for: configuration.modelName)

        self.container = .init(name: configuration.modelName, managedObjectModel: model)
        
        if let description = self.container.persistentStoreDescriptions.first {
            description.configuration = configuration.configuration
            description.type = NSInMemoryStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        } else {
            // Handle the case where there is no persistent store description
            fatalError("No persistent store descriptions found in the container.")
        }
        
        self.container.loadPersistentStores(completionHandler: { (desc, err) in
            if let err = err {
                fatalError("Error loading LOCAL STORE: \(desc): \(err)")
            }
            debugPrint("Loaded TEMPORARY STORE successfully")
        })
    }
}

extension IPersistenceManager {
    static func model(for name: String) throws -> NSManagedObjectModel {
        guard let url = Bundle.module.url(forResource: name, withExtension: "momd") else { throw SwapSDKError.msg("Could not get URL for model: \(name)") }
        guard let model = NSManagedObjectModel(contentsOf: url) else { throw SwapSDKError.msg("Could not get model for: \(url)") }
        return model
    }
}
