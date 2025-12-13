import Foundation
import BigInt
import Promises

protocol TxLockable: BaseClass {
    var queue: TransactionLock { get set }

    func waitForReceipt(txid: String) -> Promise<Void>
    func emitOnFinality(_ txid: String, event: String, args: [Any])
    func withTxLock<T>(_ asyncFn: @escaping () -> Promise<T>) -> Promise<T>
    func retryWithBackoff<T>(_ fn: @escaping () -> Promise<T>) -> Promise<T>
}

extension TxLockable {
    func emitOnFinality(_ txid: String, event: String, args: [Any]) {
        waitForReceipt(txid: txid).then { _ in
            let capitalizedEvent = "on\(event.prefix(1).uppercased())\(event.dropFirst())"
            self.info(capitalizedEvent, args)
            self.emit(event: event, args: args)
        }
    }
    
    func withTxLock<T>(_ asyncFn: @escaping () -> Promise<T>) -> Promise<T> {
        queue.run(asyncFn)
    }
    
    func retryWithBackoff<T>(_ fn: @escaping () -> Promise<T>) -> Promise<T> {
        Promise<T> { resolve, reject in
            let stages = [
                [1, 0], // 1 attempt immediately
                [10, 1000], // 10 attempts every 1 second
                // [10, 2000], // 10 attempts every 2 seconds
                // [10, 3000], // 10 attempts every 3 seconds
            ]
            
            func tryNextStage(stageIndex: Int) {
                guard stageIndex < stages.count else {
                    // All retries exhausted, try one final time to get the actual error
                    fn().then { result in
                        resolve(result)
                    }.catch { error in
                        reject(error)
                    }
                    return
                }
                
                let stage = stages[stageIndex]
                let attempts = stage[0]
                let delay = stage[1]
                
                func tryAttempt(attemptIndex: Int) {
                    fn().then { result in
                        resolve(result)
                    }.catch { error in
                        if attemptIndex == attempts - 1 {
                            // Last attempt of this stage, continue to next stage
                            tryNextStage(stageIndex: stageIndex + 1)
                        } else {
                            // More attempts in this stage
                            if delay > 0 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                                    tryAttempt(attemptIndex: attemptIndex + 1)
                                }
                            } else {
                                tryAttempt(attemptIndex: attemptIndex + 1)
                            }
                        }
                    }
                }
                
                tryAttempt(attemptIndex: 0)
            }
            
            tryNextStage(stageIndex: 0)
        }
    }
}

protocol NativeChain: BaseClass, TxLockable {
    var address: String { get }

    func start(height: BigUInt?) -> Promise<Void>
    func stop() -> Promise<Void>

    func deposit(_ liquidity: Liquidity) -> Promise<Liquidity>

    func createInvoice(_ party: Party) -> Promise<Invoice>
    func payInvoice(_ party: Party) -> Promise<Void>
    func settleInvoice(for party: Party, with secret: Data) -> Promise<Party>
    func getBlockHeight() -> Promise<UInt64>
    func fetchInvoiceTimeout(invoiceIdentifier: String) -> Promise<Int>
    func recoverLockedFunds(swap: Swap) -> Promise<Void>
}

extension NativeChain {
    func start(height: BigUInt? = 0) -> Promise<Void> {
        if let height {
            start(height: height)
        } else {
            start(height: 0)
        }
    }
}

final class NativeChainError: BaseError {
    static func invalidChain(expected: String, actual: String, context: [String: Any]? = nil) -> NativeChainError {
        let message = "invalid native chain!"
        let code = "EInvalidChain"
        var ctx: [String: Any] = ["expected": expected, "actual": actual]
        if let context = context {
            ctx.merge(context, uniquingKeysWith: { $1 })
        }
        return NativeChainError(message: message, code: code, context: ctx)
    }

    static func invalidAsset(expected: String, actual: String, context: [String: Any]? = nil) -> NativeChainError {
        let message = "invalid asset!"
        let code = "EInvalidAsset"
        var ctx: [String: Any] = ["expected": expected, "actual": actual]
        if let context = context {
            ctx.merge(context, uniquingKeysWith: { $1 })
        }
        return NativeChainError(message: message, code: code, context: ctx)
    }

    static func insufficientBalance(asset: String, required: String, available: String) -> NativeChainError {
        let message = "insufficient balance!"
        let code = "EInsufficientBalance"
        let ctx: [String: Any] = ["asset": asset, "required": required, "available": available]
        return NativeChainError(message: message, code: code, context: ctx)
    }

    static func invalidAmount(_ amount: String) -> NativeChainError {
        let message = "invalid amount!"
        let code = "EInvalidAmount"
        let ctx: [String: Any] = ["amount": amount]
        return NativeChainError(message: message, code: code, context: ctx)
    }

    static func invalidLiquidity(liquidity: String?, metadata: [String: Any]) -> NativeChainError {
        let message = "invalid liquidity!"
        let code = "EInvalidLiquidity"
        let ctx: [String: Any] = ["liquidity": liquidity as Any, "metadata": metadata]
        return NativeChainError(message: message, code: code, context: ctx)
    }

    static func invalidSwap(swap: String?, metadata: [String: Any]? = nil) -> NativeChainError {
        let message = "invalid swap!"
        let code = "EInvalidSwap"
        var ctx: [String: Any] = ["swap": swap as Any]
        if let metadata = metadata {
            ctx["metadata"] = metadata
        }
        return NativeChainError(message: message, code: code, context: ctx)
    }

    override init(message: String, code: String, context: [String: Any]? = nil, cause: Error? = nil) {
        super.init(message: message, code: code, context: context, cause: cause)
    }
}
