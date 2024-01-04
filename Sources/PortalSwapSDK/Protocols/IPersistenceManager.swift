import CoreData

protocol IPersistenceManager {
    var viewContext: NSManagedObjectContext { get }
    init(configuration: PersistenceConfiguration) throws
}
