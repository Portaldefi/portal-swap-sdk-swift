import CoreData

open class PersistentContainer: NSPersistentContainer {

    override open class func defaultDirectoryURL() -> URL {

        return super.defaultDirectoryURL()
            .appendingPathComponent("DBModel")
            .appendingPathComponent("Local")
    }
}

open class PersistentCloudKitContainer: NSPersistentCloudKitContainer {
    
    override open class func defaultDirectoryURL() -> URL {
        
        return super.defaultDirectoryURL()
            .appendingPathComponent("DBModel")
            .appendingPathComponent("Cloud")
    }
}
