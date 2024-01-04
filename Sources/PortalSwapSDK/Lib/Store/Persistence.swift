import CoreData

open class PersistentContainer: NSPersistentContainer {
    override open class func defaultDirectoryURL() -> URL {
            let url = super.defaultDirectoryURL().appendingPathComponent("DBModel/Local")
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    fatalError("Could not create directory: \(error)")
                }
            }
            return url
        }
}

open class PersistentCloudKitContainer: NSPersistentCloudKitContainer {
    override open class func defaultDirectoryURL() -> URL {
        super.defaultDirectoryURL()
            .appendingPathComponent("DBModel")
            .appendingPathComponent("Cloud")
    }
}
