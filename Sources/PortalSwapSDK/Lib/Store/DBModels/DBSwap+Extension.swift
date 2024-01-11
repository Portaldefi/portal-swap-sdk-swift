//
//  File.swift
//
//
//  Created by farid on 08.01.2024.
//

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
    
    func update(swap: Swap) throws {
        guard let context = managedObjectContext else {
            throw SwapSDKError.msg("Cannot obtain manage object context")
        }
        
        try context.performAndWait {
            self.swapID = swap.id
            self.secretHash = swap.secretHash
            self.status = swap.status
            self.timestamp = Int64(Date().timeIntervalSince1970)
            
            guard let secretSeeker = secretSeeker else {
                throw SwapSDKError.msg("Swap db entity has no seeker")
            }
            
            secretSeeker.partyID = swap.secretSeeker.id
            secretSeeker.oid = swap.secretSeeker.oid
            secretSeeker.blockchain = swap.secretSeeker.blockchain
            secretSeeker.asset = swap.secretSeeker.asset
            secretSeeker.quantity = swap.secretSeeker.quantity
            
            guard let secretHolder = secretHolder else {
                throw SwapSDKError.msg("Swap db entity has no holder")
            }
            
            secretHolder.partyID = swap.secretHolder.id
            secretHolder.oid = swap.secretHolder.oid
            secretHolder.blockchain = swap.secretHolder.blockchain
            secretHolder.asset = swap.secretHolder.asset
            secretHolder.quantity = swap.secretHolder.quantity
            
            var jsonInvoices = [[String: String]]()
            var dbInvoices = [DBInvoice]()
            
            if let seekerInvoice = swap.secretSeeker.invoice {
                jsonInvoices.append(seekerInvoice)
                
                guard let invoice = secretSeeker.invoice else {
                    throw SwapSDKError.msg("SecretSeeker has no db invocie")
                }
                
                dbInvoices.append(invoice)
            }
            
            if let holderInvoice = swap.secretHolder.invoice {
                jsonInvoices.append(holderInvoice)
                
                guard let invoice = secretHolder.invoice else {
                    throw SwapSDKError.msg("SecretHolder has no db invocie")
                }
                
                dbInvoices.append(invoice)
            }
            
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
            "id": self.swapID as Any,
            "status": self.status as Any,
            "secretHash": self.secretHash as Any,
            "secretSeeker" : [
                "asset" : self.secretSeeker?.asset as Any,
                "id": self.secretSeeker?.partyID as Any,
                "quantity" : self.secretSeeker?.quantity as Any,
                "oid" : self.secretSeeker?.oid as Any,
                "blockchain" : self.secretSeeker?.blockchain as Any
            ],
            "secretHolder" : [
                "asset" : self.secretHolder?.asset as Any,
                "id": self.secretHolder?.partyID as Any,
                "quantity" : self.secretHolder?.quantity as Any,
                "oid" : self.secretHolder?.oid as Any,
                "blockchain" : self.secretHolder?.blockchain as Any
            ]
        ]
    }
    
    func model() throws -> Swap {
        let jsonData = try JSONSerialization.data(withJSONObject: toJSON(), options: [])
        return try JSONDecoder().decode(Swap.self, from: jsonData)
    }
    
    static func entity(key: String, context: NSManagedObjectContext) throws -> DBSwap {
        try context.performAndWait {
            let dbSwaps = try context.fetch(DBSwap.fetchRequest())
            
            if let dbSwap = dbSwaps.first(where: { $0.swapID == key }) {
                return dbSwap
            } else {
                throw SwapSDKError.msg("Swap with id: \(key) is not exists in DB")
            }
        }
    }
    
    public static func entities(context: NSManagedObjectContext) throws -> [DBSwap] {
        try context.performAndWait {
            try context.fetch(DBSwap.fetchRequest())
        }
    }
    
    public static func swapModels(context: NSManagedObjectContext) throws -> [Swap] {
        try context.performAndWait {
            try context.fetch(DBSwap.fetchRequest()).compactMap{ try? $0.model() }
        }
    }
}
