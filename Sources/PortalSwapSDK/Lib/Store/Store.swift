import Promises

public class Store: BaseClass {
    var isOpen: Bool {
        false
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
        [:]
    }
    
    func put(_ namespace: String, _ key: String, _ obj: [String: Any]) throws {
        
    }
    
    func update(_ namespace: String, _ key: String) throws {
        
    }
    
    func del(id: String) throws {
        
    }
}
