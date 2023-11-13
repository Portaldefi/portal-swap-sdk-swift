public class Swap: BaseClass, Decodable {
    public var secretHash: String?
    public let secretHolder: Party
    public let secretSeeker: Party
    public let status: String
    
    public var isReceived: Bool {
        status == "received"
    }
    
    public var isCreated: Bool {
        status == "created"
    }
    
    public var isHolderInvoiceCreated: Bool {
        status == "holder.invoice.created"
    }
    
    public var isHolderInvoiceSent: Bool {
        status == "holder.invoice.sent"
    }
    
    public var isSeekerInvoiceCreated: Bool {
        status == "seeker.invoice.created"
    }
    
    public var isSeekerInvoiceSent: Bool {
        status == "seeker.invoice.sent"
    }
    
    public var isHolderPaid: Bool {
        status == "holder.invoice.paid"
    }
    
    public var isSeekerPaid: Bool {
        status == "seeker.invoice.paid"
    }
    
    public var isHolderSettled: Bool {
        status == "holder.invoice.settled"
    }
    
    public var isSeekerSettled: Bool {
        status == "seeker.invoice.settled"
    }
    
    public var isCompleted: Bool {
        status == "completed"
    }
    
    public var party: Party {
        id! == secretHolder.id ? secretHolder : secretSeeker
    }
    
    public func update(_ swap: [String: Any]) throws {
        
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secretHash = try? container.decode(String.self, forKey: .secretHash)
        status = try container.decode(String.self, forKey: .status)
        secretHolder = try container.decode(Party.self, forKey: .secretHolder)
        secretSeeker = try container.decode(Party.self, forKey: .secretSeeker)
        super.init(id: try container.decode(String.self, forKey: .id))
    }
    
    public func createInvoice() throws {
        
    }
    
    public func payInvoice() throws {
        
    }
    
    public func sendInvoice() throws {
        
    }
    
    public func settleInvoice() throws {
        
    }
    
    public func toJSON() -> [String: Any] {
        [:]
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, secretHash, secretHolder, secretSeeker, status
    }
}
