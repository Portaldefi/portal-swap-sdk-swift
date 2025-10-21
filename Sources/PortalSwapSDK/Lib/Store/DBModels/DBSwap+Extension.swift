import CoreData

extension DBSwap {
    convenience init(context: NSManagedObjectContext) {
        let entityName = String(describing: DBSwap.self)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        
        self.init(entity: entity, insertInto: context)
    }
    
    func updateFromDomainSwap(_ swap: Swap) throws {
        guard let context = managedObjectContext else {
            throw SwapSDKError.msg("Cannot obtain managed object context")
        }
        
        self.state = swap.state.rawValue
        
        switch swap.state {
        case .holderInvoiced:
            if swap.secretHash != self.secretHash?.hexString {
                self.secretHash = Data(hex: swap.secretHash)
            }
            if let invoice = swap.secretSeeker.invoice {
                self.ensureSecretSeeker(context: context)
                self.secretSeeker?.invoice = invoice
            }
            
        case .seekerInvoiced:
            if let invoice = swap.secretHolder.invoice {
                self.ensureSecretHolder(context: context)
                self.secretHolder?.invoice = invoice
            }
            
        case .holderPaid:
            if let receipt = swap.secretHolder.receipt {
                self.ensureSecretHolder(context: context)
                self.secretHolder?.receipt = receipt
            }
            
        case .seekerPaid:
            if let receipt = swap.secretSeeker.receipt {
                self.ensureSecretSeeker(context: context)
                self.secretSeeker?.receipt = receipt
            }
            
        case .holderSettled:
            if let secret = swap.secret {
                let secretHash = secret.sha256()
                
                if self.secretHash != secretHash {
                    throw SdkError(message: "secretHash mismatch: \(self.secretHash?.hexString ?? "nil") vs \(secretHash.hexString)", code: String())
                }
            }
            
        default:
            break
        }
    }
    
    private func ensureSecretSeeker(context: NSManagedObjectContext) {
        if self.secretSeeker == nil {
            self.secretSeeker = DBSwapParty(context: context)
        }
    }
    
    private func ensureSecretHolder(context: NSManagedObjectContext) {
        if self.secretHolder == nil {
            self.secretHolder = DBSwapParty(context: context)
        }
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
