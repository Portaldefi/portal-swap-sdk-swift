import Foundation
import Promises

class TransactionLock {
    private var lock: Promise<Void>
    
    init() {
        lock = Promise<Void> { resolve, _ in resolve(()) }
    }
    
    func run<T>(_ asyncFn: @escaping () -> Promise<T>) -> Promise<T> {
        let currentLock = lock
        
        let operationPromise = currentLock.then { _ in
            asyncFn()
        }.recover { _ in
            asyncFn()
        }
        
        lock = operationPromise.then { _ in
            ()
        }.recover { _ in
            ()
        }
        
        return operationPromise
    }
}

