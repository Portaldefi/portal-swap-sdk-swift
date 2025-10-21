import Foundation

class BaseError: LocalizedError, CustomStringConvertible {
    let message: String
    let code: String
    let context: [String: Any]?
    let cause: Error?

    var description: String {
        var output = "\(code): \(message)"
        if let context = context {
            output += "\n  \(context)"
        }
        if let cause = cause {
            output += "\n  Caused by: \(cause)"
        }
        return output
    }

    init(message: String, code: String, context: [String: Any]? = nil, cause: Error? = nil) {
        self.message = message
        self.code = code
        self.context = context
        self.cause = cause
    }
    
    static func unexpected(context: [String: Any]? = nil, cause: Error? = nil) -> BaseError {
        BaseError(message: "Unexpected error!", code: "EUnexpected", context: context, cause: cause)
    }
}
