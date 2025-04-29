import Foundation
import BigInt
import Promises

protocol NativeChain: BaseClass {
    var address: String { get }

    func start() async throws
    func stop() async throws

    func deposit(_ liquidity: Liquidity) -> Promise<Liquidity>
    func withdraw(_ liquidity: Liquidity) -> Promise<Liquidity>

    func createInvoice(_ party: Party) -> Promise<Invoice>
    func payInvoice(_ party: Party) -> Promise<Void>
    func settleInvoice(for party: Party, with secret: Data) -> Promise<Party>
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
