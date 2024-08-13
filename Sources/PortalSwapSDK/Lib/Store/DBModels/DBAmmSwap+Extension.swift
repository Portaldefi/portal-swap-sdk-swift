import CoreData
import BigInt

extension DBAmmSwap {
    convenience init(context: NSManagedObjectContext) {
        let entityName = String(describing: DBAmmSwap.self)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        
        self.init(entity: entity, insertInto: context)
    }
    
    func update(swap: AmmSwap) throws {
        guard let context = managedObjectContext else {
            throw SwapSDKError.msg("Cannot obtain manage object context")
        }
        
        context.performAndWait {
            self.swapId = swap.swapId
            self.status = swap.status
            self.secretHash = swap.secretHash
            self.sellerAddress = swap.sellerAddress
            self.sellNetwork = swap.sellNetwork
            self.sellAsset = swap.sellAsset
            self.sellAmount = swap.sellAmount.description
            self.buyAddress = swap.buyAddress
            self.buyNetwork = swap.buyNetwork
            self.buyAsset = swap.buyAsset
            self.buyAmount = swap.buyAmount.description
            self.buyAmountSlippage = swap.buyAmountSlippage.description
            self.tsCreation = swap.tsCreation
            
            if let buyQuantity = swap.buyQuantity?.description {
                self.buyQuantity = buyQuantity
            }
        }
    }
    
    func toJSON() -> [String: Any] {
        return [
            "swapId": swapId as Any,
            "status": status as Any,
            "secretHash": secretHash as Any,
            "sellerAddress" : sellerAddress as Any,
            "sellNetwork" : sellNetwork as Any,
            "sellAsset": sellAsset as Any,
            "sellAmount": BigUInt(stringLiteral: sellAmount!) as Any,
            "buyAddress": buyAddress as Any,
            "buyNetwork": buyNetwork as Any,
            "buyAsset": buyAsset as Any,
            "buyAmount": BigUInt(stringLiteral: buyAmount!) as Any,
            "buyQuantity": buyQuantity as Any,
            "buyAmountSlippage": BigUInt(stringLiteral: buyAmountSlippage!) as Any,
            "tsCreation": tsCreation as Any
        ]
    }
        
    static func entity(key: String, context: NSManagedObjectContext) throws -> DBAmmSwap {
        try context.performAndWait {
            let dbSwaps = try context.fetch(DBAmmSwap.fetchRequest())
            
            if let dbSwap = dbSwaps.first(where: { $0.swapId == key }) {
                return dbSwap
            } else {
                throw SwapSDKError.msg("Swap with id: \(key) is not exist in DB")
            }
        }
    }
    
    static func entities(context: NSManagedObjectContext) throws -> [DBAmmSwap] {
        try context.performAndWait {
            try context.fetch(DBAmmSwap.fetchRequest())
        }
    }
}

