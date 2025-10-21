public enum SwapOperationStatus {
    case none,
         matching,
         matched,
         canceled,
         swapping,
         failed(String),
         succeded,
         sdkStopped,
         initiated,
         depositing,
         openingOrder,
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
        case .openingOrder:
            return "Opening order"
        case .matching:
            return "Swap matching"
        case .canceled:
            return "Canceled"
        case .swapping:
            return "Creating invoice"
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
            return "Withdrawing deposit"
        }
    }
}
