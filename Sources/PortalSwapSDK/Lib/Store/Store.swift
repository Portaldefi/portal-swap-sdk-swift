import Foundation
import Promises

public class Store: BaseClass {
    var isOpen: Bool {
        true
    }
    
    init() {
        super.init()
    }
    
    func open() -> Promise<Void> {
        emit(event: "open", args: [])
        return Promise {()}
    }
    
    func close() -> Promise<Void> {
        emit(event: "close", args: [])
        return Promise {()}
    }
    
    func get(_ namespace: String, _ key: String) throws -> [String: Any] {
        switch namespace {
        case "secrets":
            if let secret = UserDefaults.standard.data(forKey: key) {
                return ["secret" : secret]
            } else {
                return [:]
            }
        default:
            return [:]
        }
    }
    
    func put(_ namespace: String, _ key: String, _ obj: [String: Any]) throws {
        switch namespace {
        case "secrets":
            if
                let dataDict = obj as? [String:String],
                let secretString = dataDict["secret"],
                let secret = Utils.hexToData(secretString)
            {
                UserDefaults.standard.set(secret, forKey: key)
            }
        default:
            break
        }
    }
    
    func update(_ namespace: String, _ key: String) throws {
        
    }
    
    func del(id: String) throws {
        
    }
}
