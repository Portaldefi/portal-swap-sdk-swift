import Foundation
import Promises

class TransactionLock {
    private var lock: Promise<Any>
    
    init() {
        lock = Promise<Any> { return () }
    }
    
    func run<T>(_ asyncFn: @escaping () -> Promise<T>) -> Promise<T> {
        let currentLock = lock
        
        let operationPromise = currentLock.then { _ in
            asyncFn()
        }.recover { _ in
            asyncFn()
        }
        
        lock = Promise<Any> { resolve, reject in
            operationPromise.then { _ in
                resolve(())
            }.catch { _ in
                resolve(())
            }
        }
        
        return operationPromise
    }
}


