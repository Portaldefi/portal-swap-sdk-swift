import Foundation
import CoreData
import Promises

final class Store: BaseClass {
    private let accountId: String
    private var persistenceManager: LocalPersistenceManager?
    
    var isOpen: Bool {
        persistenceManager != nil
    }
    
    init(accountId: String) {
        self.accountId = accountId
        
        super.init(id: "Store")
    }
    
    func start() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }

            persistenceManager = try LocalPersistenceManager.manager(accountId: accountId)
            emit(event: "open", args: [])
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }

            persistenceManager = nil
            emit(event: "close", args: [])
        }
    }
    
    func put(swap: Swap) throws {
        guard let manager = persistenceManager else {
            throw StoreError.managerNotFound()
        }
        
        let newEntity = manager.swapEntity()
        try newEntity.update(swap: swap)
        
        debug("Put swap with ID: \(newEntity.swapId?.hexString ?? "Unknown")")
        
        try manager.saveContext()
    }
    
    func get(swapId: String) throws -> Swap {
        guard let manager = persistenceManager else {
            throw StoreError.managerNotFound()
        }
        
        let dbSwap = try manager.swap(swapId: swapId)
        return try Swap(record: dbSwap)
    }
    
    func createSecret() throws -> String {
        guard let manager = persistenceManager else {
            throw StoreError.managerNotFound()
        }
        
        let (secret, secretHash) = Utils.createSecret()
        let secretEntity = manager.secretEntity()
        secretEntity.data = secret
        secretEntity.secretHash = secretHash.hexString
        
        try manager.saveContext()
        
        return secretHash.hexString
    }
    
    func getSecret(key: String) throws -> Data {
        guard let manager = persistenceManager else {
            throw StoreError.managerNotFound()
        }
        
        let dbSecret = try manager.secret(key: key)
        
        guard let secretData = dbSecret.data else {
            throw StoreError.entityNotFound()
        }
        
        return secretData
    }
    
    func update(swap: Swap) throws {
        guard let manager = persistenceManager else {
            throw StoreError.managerNotFound()
        }
        let dbSwap = try manager.swap(swapId: swap.id)
        try dbSwap.update(swap: swap)
        try manager.saveContext()
    }
}

final class StoreError: BaseError {
    static func entityNotFound() -> StoreError {
        let message = "InstanceUnavailable!"
        let code = "ENotFound"
        return StoreError(message: message, code: code, context: [:])
    }
    
    static func managerNotFound() -> StoreError {
        let message = "Cannot obtain persistenceManager!"
        let code = "EManagerNotFound"
        return StoreError(message: message, code: code, context: [:])
    }
    // MARK: - Initializer
    
    override init(message: String, code: String, context: [String: Any]? = nil, cause: Error? = nil) {
        super.init(message: message, code: code, context: context, cause: cause)
    }
}
