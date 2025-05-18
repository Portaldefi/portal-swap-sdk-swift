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
            swapId = swap.swapId.hexString
            
            swapTxHash = swap.swapTxHash
            
            liquidityPoolId = swap.liquidityPoolId.hexString
            secretHash = swap.secretHash.hexString
            sellAssetSymbol = swap.sellAssetSymbol
            sellAsset = swap.sellAsset.hex(eip55: true)
            sellAmount = swap.sellAmount.description
            
            sellAssetTx = swap.sellAssetTx
            
            buyAssetSymbol = swap.buyAssetSymbol
            buyAsset = swap.buyAsset.hex(eip55: true)
            buyAmount = swap.buyAmount.description
            
            buyAssetTx = swap.buyAssetTx
            
            slippage = swap.slippage.description
            swapCreation = swap.swapCreation.description
            swapOwner = swap.swapOwner.hex(eip55: true)
            status = swap.status
            buyId = swap.buyId
        }
    }
    
    func toJSON() -> [String: Any] {
        return [
            "swapId": swapId as Any,
            "swapTxHash": swapTxHash as Any,
            "liquidityPoolId": liquidityPoolId as Any,
            "secretHash": secretHash as Any,
            "sellAsset": sellAsset as Any,
            "sellAmount": BigUInt(stringLiteral: sellAmount!) as Any,
            "sellAssetTx": sellAssetTx as Any,
            "buyAsset": buyAsset as Any,
            "buyAmount": BigUInt(stringLiteral: buyAmount!) as Any,
            "buyAssetTx": buyAssetTx as Any,
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

