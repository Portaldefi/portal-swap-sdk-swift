import CoreData

extension DBSwapTransaction {
    static func entities(context: NSManagedObjectContext) throws -> [DBSwapTransaction] {
        try context.performAndWait {
            try context.fetch(DBSwapTransaction.fetchRequest())
        }
    }
    
    static func update(accountId: String, key: String, transaction: SwapTransaction, context: NSManagedObjectContext) throws {
        try context.performAndWait {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let jsonData = try encoder.encode(transaction)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            let fetchRequest: NSFetchRequest<DBSwapTransaction> = DBSwapTransaction.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "txHash == %@", key)
            
            let existingEntity = try context.fetch(fetchRequest).first
            let entity = existingEntity ?? DBSwapTransaction(context: context)
            
            entity.accountId = accountId
            entity.txHash = key
            entity.jsonData = jsonString
            
            try context.save()
        }
    }
}
