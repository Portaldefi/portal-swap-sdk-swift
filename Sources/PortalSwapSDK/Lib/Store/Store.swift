import Foundation
import CoreData
import Promises

class Store: BaseClass {
    private var persistenceManager: LocalPersistenceManager?
    
    var isOpen: Bool {
        persistenceManager != nil
    }
    
    init() {
        super.init()
    }
    
    func open() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                persistenceManager = try LocalPersistenceManager(
                    configuration: .init(
                        modelName: "DBModel",
                        cloudIdentifier: String(),
                        configuration: "Local"
                    )
                )
                
                emit(event: "open", args: [])
                resolve(())
            } catch {
               reject(error)
            }
        }
    }

    func close() -> Promise<Void> {
        emit(event: "close", args: [])
        return Promise {()}
    }
    
    func get(_ namespace: StoreNamespace, _ key: String) throws -> [String: Any] {
        guard let persistenceManager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }

        switch namespace {
        case .secrets:
            let request = DBSecret.fetchRequest() as NSFetchRequest<DBSecret>
            let secrets = try persistenceManager.viewContext.fetch(request)
            
            if let secret = secrets.first(where: { $0.secretHash == key }) {
                return ["secret" : secret.data as Any]
            } else {
                throw SwapSDKError.msg("secret with id: \(key) is not exists in DB")
            }
        case .swaps:
            let request = DBSwap.fetchRequest() as NSFetchRequest<DBSwap>
            let swaps = try persistenceManager.viewContext.fetch(request)
            
            if let swap = swaps.first(where: { $0.swapID == key }) {
                return [
                    "id": swap.swapID as Any,
                    "status": swap.status as Any,
                    "secretHash": swap.secretHash as Any,
                    "secretSeeker" : [
                        "asset" : swap.secretSeeker?.asset as Any,
                        "id": swap.secretSeeker?.partyID as Any,
                        "quantity" : swap.secretSeeker?.quantity as Any,
                        "oid" : swap.secretSeeker?.oid as Any,
                        "blockchain" : swap.secretSeeker?.blockchain as Any
                    ],
                    "secretHolder" : [
                        "asset" : swap.secretHolder?.asset as Any,
                        "id": swap.secretHolder?.partyID as Any,
                        "quantity" : swap.secretHolder?.quantity as Any,
                        "oid" : swap.secretHolder?.oid as Any,
                        "blockchain" : swap.secretHolder?.blockchain as Any
                    ]
                ]
            } else {
                throw SwapSDKError.msg("Swap with id: \(key) is not exists in DB")
            }
        }
    }
    
    func put(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
        guard let persistenceManager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }

        switch namespace {
        case .secrets:
            if
                let dataDict = obj as? [String:String],
                let swapId = dataDict["swap"],
                let secretString = dataDict["secret"],
                let secret = Utils.hexToData(secretString)
            {
                let newEntity = DBSecret(context: persistenceManager.viewContext)
                
                newEntity.data = secret
                newEntity.swapID = swapId
                newEntity.secretHash = key
            } else {
                throw SwapSDKError.msg("Cannot unwrap secret data")
            }
        case .swaps:
            let jsonData = try JSONSerialization.data(withJSONObject: obj, options: [])
            let swap = try JSONDecoder().decode(Swap.self, from: jsonData)
            
            let request = DBSwap.fetchRequest() as NSFetchRequest<DBSwap>
            let swaps = try persistenceManager.viewContext.fetch(request)
            
            if let dbSwap = swaps.first(where: { $0.swapID == key }) {
                dbSwap.swapID = swap.id
                dbSwap.secretHash = swap.secretHash
                dbSwap.status = swap.status
                
                dbSwap.secretSeeker?.partyID = swap.secretSeeker.id
                dbSwap.secretSeeker?.oid = swap.secretSeeker.oid
                dbSwap.secretSeeker?.blockchain = swap.secretSeeker.blockchain
                dbSwap.secretSeeker?.asset = swap.secretSeeker.asset
                dbSwap.secretSeeker?.quantity = swap.secretSeeker.quantity
                
                if let seekerInvoice = swap.secretSeeker.invoice {
                    if seekerInvoice["request"] != nil {
                        // Lightning Invoice
                        dbSwap.secretSeeker?.invoice?.lightningInvoice?.invoiceID = swap.secretSeeker.invoice?["id"]
                        dbSwap.secretSeeker?.invoice?.lightningInvoice?.request = swap.secretSeeker.invoice?["request"]
                        dbSwap.secretSeeker?.invoice?.lightningInvoice?.swap = swap.secretSeeker.invoice?["swap"]
                    } else {
                        //EVM Invoice
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.blockHash = swap.secretSeeker.invoice?["blockHash"]
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.from = swap.secretSeeker.invoice?["from"]
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.to = swap.secretSeeker.invoice?["to"]
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.transactionHash = swap.secretSeeker.invoice?["transactionHash"]
                    }
                } else if let holderInvoice = swap.secretHolder.invoice {
                    if holderInvoice["request"] != nil {
                        // Lightning Invoice
                        dbSwap.secretHolder?.invoice?.lightningInvoice?.invoiceID = swap.secretSeeker.invoice?["id"]
                        dbSwap.secretHolder?.invoice?.lightningInvoice?.request = swap.secretSeeker.invoice?["request"]
                        dbSwap.secretHolder?.invoice?.lightningInvoice?.swap = swap.secretSeeker.invoice?["swap"]
                    } else {
                        //EVM Invoice
                        dbSwap.secretHolder?.invoice?.evmInvoice?.blockHash = swap.secretSeeker.invoice?["blockHash"]
                        dbSwap.secretHolder?.invoice?.evmInvoice?.from = swap.secretSeeker.invoice?["from"]
                        dbSwap.secretHolder?.invoice?.evmInvoice?.to = swap.secretSeeker.invoice?["to"]
                        dbSwap.secretHolder?.invoice?.evmInvoice?.transactionHash = swap.secretSeeker.invoice?["transactionHash"]
                    }
                }
                                    
                dbSwap.secretHolder?.partyID = swap.secretHolder.id
                dbSwap.secretHolder?.oid = swap.secretHolder.oid
                dbSwap.secretHolder?.blockchain = swap.secretHolder.blockchain
                dbSwap.secretHolder?.asset = swap.secretHolder.asset
                dbSwap.secretHolder?.quantity = swap.secretHolder.quantity
            } else {
                let newEntity = DBSwap(context: persistenceManager.viewContext)
                
                newEntity.swapID = swap.id
                newEntity.secretHash = swap.secretHash
                newEntity.status = swap.status
                
                let secretSeeker = DBParty(context: persistenceManager.viewContext)
                secretSeeker.partyID = swap.secretSeeker.id
                secretSeeker.oid = swap.secretSeeker.oid
                secretSeeker.blockchain = swap.secretSeeker.blockchain
                secretSeeker.asset = swap.secretSeeker.asset
                secretSeeker.quantity = swap.secretSeeker.quantity
                secretSeeker.invoice = DBInvoice(context: persistenceManager.viewContext)
                
                newEntity.secretSeeker = secretSeeker
                
                let secretHolder = DBParty(context: persistenceManager.viewContext)
                secretHolder.partyID = swap.secretHolder.id
                secretHolder.oid = swap.secretHolder.oid
                secretHolder.blockchain = swap.secretHolder.blockchain
                secretHolder.asset = swap.secretHolder.asset
                secretHolder.quantity = swap.secretHolder.quantity
                secretHolder.invoice = DBInvoice(context: persistenceManager.viewContext)
                
                newEntity.secretHolder = secretHolder
            }
        }
        
        try persistenceManager.viewContext.save()
    }
    
    func update(_ namespace: StoreNamespace, _ key: String, _ obj: [String: Any]) throws {
        guard let persistenceManager = persistenceManager else {
            throw SwapSDKError.msg("Cannot obtain persistenceManager")
        }
        
        switch namespace {
        case .swaps:
            let jsonData = try JSONSerialization.data(withJSONObject: obj, options: [])
            let swap = try JSONDecoder().decode(Swap.self, from: jsonData)
            
            let request = DBSwap.fetchRequest() as NSFetchRequest<DBSwap>
            let swaps = try persistenceManager.viewContext.fetch(request)
                
            if let dbSwap = swaps.first(where: { $0.swapID == key }) {
                dbSwap.swapID = swap.id
                dbSwap.secretHash = swap.secretHash
                dbSwap.status = swap.status
                
                dbSwap.secretSeeker?.partyID = swap.secretSeeker.id
                dbSwap.secretSeeker?.oid = swap.secretSeeker.oid
                dbSwap.secretSeeker?.blockchain = swap.secretSeeker.blockchain
                dbSwap.secretSeeker?.asset = swap.secretSeeker.asset
                dbSwap.secretSeeker?.quantity = swap.secretSeeker.quantity
                
                if let seekerInvoice = swap.secretSeeker.invoice {
                    if seekerInvoice["request"] != nil {
                        // Lightning Invoice
                        dbSwap.secretSeeker?.invoice?.lightningInvoice?.invoiceID = swap.secretSeeker.invoice?["id"]
                        dbSwap.secretSeeker?.invoice?.lightningInvoice?.request = swap.secretSeeker.invoice?["request"]
                        dbSwap.secretSeeker?.invoice?.lightningInvoice?.swap = swap.secretSeeker.invoice?["swap"]
                    } else {
                        //EVM Invoice
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.blockHash = swap.secretSeeker.invoice?["blockHash"]
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.from = swap.secretSeeker.invoice?["from"]
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.to = swap.secretSeeker.invoice?["to"]
                        dbSwap.secretSeeker?.invoice?.evmInvoice?.transactionHash = swap.secretSeeker.invoice?["transactionHash"]
                    }
                } else if let holderInvoice = swap.secretHolder.invoice {
                    if holderInvoice["request"] != nil {
                        // Lightning Invoice
                        dbSwap.secretHolder?.invoice?.lightningInvoice?.invoiceID = swap.secretSeeker.invoice?["id"]
                        dbSwap.secretHolder?.invoice?.lightningInvoice?.request = swap.secretSeeker.invoice?["request"]
                        dbSwap.secretHolder?.invoice?.lightningInvoice?.swap = swap.secretSeeker.invoice?["swap"]
                    } else {
                        //EVM Invoice
                        dbSwap.secretHolder?.invoice?.evmInvoice?.blockHash = swap.secretSeeker.invoice?["blockHash"]
                        dbSwap.secretHolder?.invoice?.evmInvoice?.from = swap.secretSeeker.invoice?["from"]
                        dbSwap.secretHolder?.invoice?.evmInvoice?.to = swap.secretSeeker.invoice?["to"]
                        dbSwap.secretHolder?.invoice?.evmInvoice?.transactionHash = swap.secretSeeker.invoice?["transactionHash"]
                    }
                }
                                    
                dbSwap.secretHolder?.partyID = swap.secretHolder.id
                dbSwap.secretHolder?.oid = swap.secretHolder.oid
                dbSwap.secretHolder?.blockchain = swap.secretHolder.blockchain
                dbSwap.secretHolder?.asset = swap.secretHolder.asset
                dbSwap.secretHolder?.quantity = swap.secretHolder.quantity
                
                debug("Updating db swap with status: \(dbSwap.status ?? "Unknown")")
                
                try persistenceManager.viewContext.save()
            } else {
                throw SwapSDKError.msg("Swap with id: \(key) is not exists in DB")
            }
        default:
            break
        }
    }
    
    func del(id: String) throws {
        
    }
}
