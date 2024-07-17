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
        
        try context.performAndWait {
            self.swapID = swap.swapId
            self.secretHash = swap.secretHash
            self.status = swap.status
            self.timestamp = Int64(Date().timeIntervalSince1970)
            
            var jsonInvoices = [[String: String]]()
            var dbInvoices = [DBInvoice]()
            
//            if let seekerInvoice = swap.secretSeeker.invoice {
//                jsonInvoices.append(seekerInvoice)
//                
//                guard let invoice = secretSeeker.invoice else {
//                    throw SwapSDKError.msg("SecretSeeker has no db invocie")
//                }
//                
//                dbInvoices.append(invoice)
//            }
//            
//            if let holderInvoice = swap.secretHolder.invoice {
//                jsonInvoices.append(holderInvoice)
//                
//                guard let invoice = secretHolder.invoice else {
//                    throw SwapSDKError.msg("SecretHolder has no db invocie")
//                }
//                
//                dbInvoices.append(invoice)
//            }
            
            guard !jsonInvoices.isEmpty && !dbInvoices.isEmpty && jsonInvoices.count == dbInvoices.count else { return }
            
            for (json, dbInvoice) in zip(jsonInvoices, dbInvoices) {
                if json.contains(where: { $0.key == "request"}) {
                    //Lightning Invoice
                    if let lightningInvoice = dbInvoice.lightningInvoice {
                        lightningInvoice.invoiceID = json["id"]
                        lightningInvoice.request = json["request"]
                        lightningInvoice.swap = json["swap"]
                    } else {
                        let entityName = String(describing: DBLightningInvoice.self)
                        let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)!
                        let lightningInvoice = DBLightningInvoice(entity: entity, insertInto: context)
                        
                        lightningInvoice.invoiceID = json["id"]
                        lightningInvoice.request = json["request"]
                        lightningInvoice.swap = json["swap"]
                        
                        dbInvoice.lightningInvoice = lightningInvoice
                    }
                } else if json.contains(where: { $0.key == "transactionHash"}) {
                    // EMV Invoice
                    if let evmInvoice = dbInvoice.evmInvoice {
                        evmInvoice.blockHash = json["blockHash"]
                        evmInvoice.from = json["from"]
                        evmInvoice.to = json["to"]
                        evmInvoice.transactionHash = json["transactionHash"]
                    } else {
                        let entityName = String(describing: DBEvmInvoice.self)
                        let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)!
                        let evmInvoice = DBEvmInvoice(entity: entity, insertInto: context)
                        
                        evmInvoice.blockHash = json["blockHash"]
                        evmInvoice.from = json["from"]
                        evmInvoice.to = json["to"]
                        evmInvoice.transactionHash = json["transactionHash"]
                        
                        dbInvoice.evmInvoice = evmInvoice
                    }
                } else {
                    throw SwapSDKError.msg("Unknown invoice type")
                }
            }
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
