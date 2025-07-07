import CoreData

extension DBSwap {
    convenience init(context: NSManagedObjectContext) {
        let entityName = String(describing: DBSwap.self)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        
        self.init(entity: entity, insertInto: context)
    }
    
    func update(swap: Swap) throws {
        guard let context = managedObjectContext else {
            throw SwapSDKError.msg("Cannot obtain manage object context")
        }
                        
        context.performAndWait {
            self.swapId = Data(hex: swap.id)
            self.state = swap.state.rawValue
            self.secretHash = Data(hex: swap.secretHash)
            
            let secretSeeker = swap.secretSeeker

            self.secretSeeker = DBSwapParty(context: context)
            
            self.secretSeeker!.amount = secretSeeker.amount.description
            self.secretSeeker!.chain = secretSeeker.chain
            self.secretSeeker!.symbol = secretSeeker.symbol
            self.secretSeeker!.amount = secretSeeker.amount.description
            
            self.secretSeeker!.invoice = secretSeeker.invoice
                
            self.secretSeeker!.receipt = secretSeeker.receipt
            self.secretSeeker!.contractAddress = secretSeeker.contractAddress
            self.secretSeeker!.portalAddress = secretSeeker.portalAddress.hex(eip55: false)

            let secretHolder = swap.secretHolder
            
            self.secretHolder = DBSwapParty(context: context)
            self.secretHolder!.amount = secretHolder.amount.description
            self.secretHolder!.chain = secretHolder.chain
            self.secretHolder!.symbol = secretHolder.symbol
            self.secretHolder!.amount = secretHolder.amount.description
            
            self.secretHolder!.invoice = secretHolder.invoice
            
            self.secretHolder!.receipt = secretHolder.receipt
            self.secretHolder!.contractAddress = secretHolder.contractAddress
            self.secretHolder!.portalAddress = secretHolder.portalAddress.hex(eip55: false)
        }
    }
    
    static func entities(context: NSManagedObjectContext) throws -> [DBSwap] {
        try context.performAndWait {
            try context.fetch(DBSwap.fetchRequest())
        }
    }
    
    static func entity(key: String, context: NSManagedObjectContext) throws -> DBSwap {
        try context.performAndWait {
            let dbSwaps = try context.fetch(DBSwap.fetchRequest())
            
            if let dbSwap = dbSwaps.first(where: { $0.swapId!.hexString == key }) {
                return dbSwap
            } else {
                throw StoreError.entityNotFound()
            }
        }
    }
}
