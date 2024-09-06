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
            self.swapId = swap.swapId.hexString
            self.liquidityPoolId = swap.liquidityPoolId.hexString
            self.secretHash = swap.secretHash.hexString
            self.sellAssetSymbol = swap.sellAssetSymbol
            self.sellAsset = swap.sellAsset.hex(eip55: true)
            self.sellAmount = swap.sellAmount.description
            self.buyAssetSymbol = swap.buyAssetSymbol
            self.buyAsset = swap.buyAsset.hex(eip55: true)
            self.buyAmount = swap.buyAmount.description
            self.slippage = swap.slippage.description
            self.swapCreation = swap.swapCreation.description
            self.swapOwner = swap.swapOwner.hex(eip55: true)
            self.status = swap.status
            self.buyId = swap.buyId
        }
    }
    
    func toJSON() -> [String: Any] {
        return [
            "swapId": swapId as Any,
            "liquidityPoolId": liquidityPoolId as Any,
            "secretHash": secretHash as Any,
            "sellAsset": sellAsset as Any,
            "sellAmount": BigUInt(stringLiteral: sellAmount!) as Any,
            "buyAsset": buyAsset as Any,
            "buyAmount": BigUInt(stringLiteral: buyAmount!) as Any,
            "slippage": BigUInt(stringLiteral: slippage!) as Any,
            "swapOwner": swapOwner as Any,
            "swapCreation": swapCreation as Any,
            "status": status as Any,
            "buyId": buyId as Any

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

