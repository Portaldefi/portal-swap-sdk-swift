import CoreData

extension DBSwap {
    convenience init(context: NSManagedObjectContext) {
        let entityName = String(describing: DBSwap.self)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        
        self.init(entity: entity, insertInto: context)
        
        let secretSeeker = DBParty(context: context)
        secretSeeker.invoice = DBInvoice(context: context)
        
        self.secretSeeker = secretSeeker
        
        let secretHolder = DBParty(context: context)
        secretHolder.invoice = DBInvoice(context: context)
        
        self.secretHolder = secretHolder
        self.timestamp = Int64(Date().timeIntervalSince1970)
    }
    
    func update(swap: AmmSwap) throws {
        guard let context = managedObjectContext else {
            throw SwapSDKError.msg("Cannot obtain manage object context")
        }
        
        context.performAndWait {
            self.swapID = swap.swapId.hexString
            self.secretHash = swap.secretHash.hexString
            self.status = swap.status
            self.timestamp = Int64(Date().timeIntervalSince1970)
        }
    }
    
    func toJSON() -> [String: Any] {
        return [
            "id": swapID as Any,
            "status": status as Any,
            "secretHash": secretHash as Any,
            "secretSeeker" : [
                "asset" : secretSeeker?.asset as Any,
                "id": secretSeeker?.partyID as Any,
                "quantity" : secretSeeker?.quantity as Any,
                "oid" : secretSeeker?.oid as Any,
                "blockchain" : secretSeeker?.blockchain as Any
            ],
            "secretHolder" : [
                "asset" : secretHolder?.asset as Any,
                "id": secretHolder?.partyID as Any,
                "quantity" : secretHolder?.quantity as Any,
                "oid" : secretHolder?.oid as Any,
                "blockchain" : secretHolder?.blockchain as Any
            ]
        ]
    }
        
    static func entity(key: String, context: NSManagedObjectContext) throws -> DBSwap {
        try context.performAndWait {
            let dbSwaps = try context.fetch(DBSwap.fetchRequest())
            
            if let dbSwap = dbSwaps.first(where: { $0.swapID == key }) {
                return dbSwap
            } else {
                throw SwapSDKError.msg("Swap with id: \(key) is not exist in DB")
            }
        }
    }
    
    static func entities(context: NSManagedObjectContext) throws -> [DBSwap] {
        try context.performAndWait {
            try context.fetch(DBSwap.fetchRequest())
        }
    }
}
