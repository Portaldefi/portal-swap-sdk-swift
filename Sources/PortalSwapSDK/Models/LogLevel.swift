enum LogLevel {
    case debug, info, warn, error, unknown
    
    static func level(_ level: String) -> Self {
        switch level {
        case "debug":
            return .debug
        case "info":
            return .info
        case "warn":
            return .warn
        case "error":
            return .error
        default:
            return .unknown
        }
    }
}
