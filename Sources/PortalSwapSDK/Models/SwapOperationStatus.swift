public enum SwapOperationStatus {
    case none,
         matching,
         canceled,
         swapping,
         failed(String),
         succeded,
         sdkStopped,
         initiated,
         depositing,
         matched,
         holderInvoiced,
         seekerInvoiced,
         holderPaid,
         seekerPaid,
         holderSettled,
         seekerSettled,
         withdrawing
    
    public var description: String {
        switch self {
        case .none:
            return String()
        case .matching:
            return "Matching"
        case .canceled:
            return "Canceled"
        case .swapping:
            return "Swapping"
        case .failed(let reason):
            return "Failed: \(reason)"
        case .succeded:
            return "Succeeded"
        case .sdkStopped:
            return "SDK stopped"
        case .initiated:
            return "Swap initiated"
        case .depositing:
            return "Depositing"
        case .matched:
            return "Swap matched"
        case .holderInvoiced:
            return "Holder invoiced"
        case .seekerInvoiced:
            return "Seeker invoiced"
        case .holderPaid:
            return "Holder paid"
        case .seekerPaid:
            return "Seeker paid"
        case .holderSettled:
            return "Holder settled"
        case .seekerSettled:
            return "Seeker settled"
        case .withdrawing:
            return "Withdraw in-progress"
        }
    }
}
