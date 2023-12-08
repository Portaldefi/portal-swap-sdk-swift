import Foundation
import CoreData

public class TemporaryPersistenceManager: IPersistenceManager {
    
    public var viewContext: NSManagedObjectContext { container.viewContext }
    
    var container: PersistentContainer
    
    required public init(
        configuration: PersistenceConfiguration
    ) {
        
        let model = TemporaryPersistenceManager.model(for: configuration.modelName)

        self.container = .init(name: configuration.modelName,
                               managedObjectModel: model)

        self.container.persistentStoreDescriptions
            .first?
            .configuration = configuration.configuration
        
        self.container.persistentStoreDescriptions
            .first?
            .type = NSInMemoryStoreType
        
        self.container.loadPersistentStores(completionHandler: { (desc, err) in
            
            if let err = err {
                
                fatalError("Error loading TEMPORARY STORE: \(desc): \(err)")
            }
            
            debugPrint("Loaded TEMPORARY STORE successfully")
        })
    }
}

extension IPersistenceManager {
    
    static func model(for name: String) -> NSManagedObjectModel {
        
        guard let url = Bundle.module.url(forResource: name, withExtension: "mom") else { fatalError("Could not get URL for model: \(name)") }

        guard let model = NSManagedObjectModel(contentsOf: url) else { fatalError("Could not get model for: \(url)") }

        return model
    }
}
