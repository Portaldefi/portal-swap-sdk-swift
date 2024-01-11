//
//  File.swift
//  
//
//  Created by farid on 08.01.2024.
//

import CoreData

extension DBSecret {
    func update(json: [String: Any], key: String) throws {
        guard let context = managedObjectContext else {
            throw SwapSDKError.msg("Cannot obtain manage object context")
        }
        
        if
            let dataDict = json as? [String: String],
            let swapId = dataDict["swap"],
            let secretString = dataDict["secret"],
            let secret = Utils.hexToData(secretString)
        {
            context.performAndWait {
                self.data = secret
                self.swapID = swapId
                self.secretHash = key
            }
        } else {
            throw SwapSDKError.msg("Cannot unwrap secret data")
        }
    }
    
    static func entity(key: String, context: NSManagedObjectContext) throws -> DBSecret {
        try context.performAndWait {
            let dbSecrets = try context.fetch(DBSecret.fetchRequest())
            
            if let secret = dbSecrets.first(where: { $0.secretHash == key }) {
                return secret
            } else {
                throw SwapSDKError.msg("secret with id: \(key) is not exists in DB")
            }
        }
    }
    
    func toJSON() -> [String: Any] {
        ["secret" : self.data as Any]
    }
}
