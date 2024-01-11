import Foundation
import Promises

public class Swap: BaseClass, Codable {
    private var sdk: Sdk?

    public var secretHolder: Party
    public var secretSeeker: Party
    public var status: String
    
    public var secretHash: String? {
        didSet {
            status = "created"
            emit(event: "created", args: [self])
        }
    }
    
    public var isReceived: Bool {
        status == "received"
    }
    
    public var party: Party {
        sdk?.id == secretHolder.id ? secretHolder : secretSeeker
    }
    
    public var partyType: String {
        party == secretHolder ? "holder" : "seeker"
    }
    
    public var counterparty: Party {
        sdk?.id == secretHolder.id ? secretSeeker : secretHolder
    }
    
    func update(sdk: Sdk) {
        self.sdk = sdk
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secretHash = try? container.decode(String.self, forKey: .secretHash)
        status = try container.decode(String.self, forKey: .status)
        secretHolder = try container.decode(Party.self, forKey: .secretHolder)
        secretHolder.isSecretHolder = true
        secretSeeker = try container.decode(Party.self, forKey: .secretSeeker)
        secretSeeker.isSecretSeeker = true
        super.init(id: try container.decode(String.self, forKey: .id))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(secretHash, forKey: .secretHash)
        try container.encode(secretSeeker, forKey: .secretSeeker)
        try container.encode(secretHolder, forKey: .secretHolder)
    }
        
    public func createInvoice() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            guard let blockchains = sdk?.blockchains else {
                return reject(SwapSDKError.msg("cannot get blockchains"))
            }
            
            guard let store = sdk?.store else {
                return reject(SwapSDKError.msg("cannot get store"))
            }
            
            guard let counterPartyBlockchainID = counterparty.blockchain.split(separator: ".").first else {
                return reject(SwapSDKError.msg("cannot get counterPartyBlockchainID"))
            }
            
            guard let blockchain = blockchains.blockchain(id: String(counterPartyBlockchainID)) else {
                return reject(SwapSDKError.msg("cannot get blockchain"))
            }
                    
            blockchain.once("invoice.paid") { [unowned self] _ in
                if self.party.isSecretSeeker {
                    self.status = "holder.invoice.paid"
                    self.emit(event: self.status, args: [self])
                } else if self.party.isSecretHolder {
                    self.status = "seeker.invoice.paid"
                    self.emit(event: self.status, args: [self])
                } else {
                    self.error("unexpected code branch!", self)
                }
            }
            
            if party.isSecretSeeker {
                guard let blockchainId = party.blockchain.split(separator: ".").first else {
                    return reject(SwapSDKError.msg("cannot get partyBlockchainID"))
                }
                
                guard let blockchain = blockchains.blockchain(id: String(blockchainId)) else {
                    return reject(SwapSDKError.msg("cannot get blockchain"))
                }
                
                blockchain.once("invoice.settled") { [unowned self] response in
                    guard
                        let dict = response.first as? [String: Any],
                        let ID = dict["id"] as? String,
                        let swap = dict["swap"] as? [String: String],
                        let swapId = swap["id"],
                        let secret = swap["secret"]
                    else {
                        return
                    }
                                        
                    try? store.put(.secrets, String(ID.dropFirst(2)), [
                        "secret": secret,
                        "swap": swapId
                    ])
                    
                    _ = self.settleInvoice()
                }
            }
                        
            counterparty.swap = self
            
            blockchain.createInvoice(party: counterparty).then { [weak self] invoice in
                guard let self = self else {
                    return reject(SwapSDKError.msg("Cannot handle self"))
                }
                
                self.counterparty.invoice = invoice
                
                status = "\(partyType).invoice.created"
                emit(event: status, args: [self])
                
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
    
    public func sendInvoice() throws -> Promise<Data> {
        guard let network = sdk?.network else {
            throw SwapSDKError.msg("Cannot fetch network")
        }
        status = "\(partyType).invoice.sent"

        let args = [
            "method": "PATCH",
            "path": "/api/v1/swap"
        ]
        
        return network.request(args: args, data: ["swap": self.toJSON()])
    }
    
    public func payInvoice() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            guard let blockchains = sdk?.blockchains else {
                return reject(SwapSDKError.msg("Cannot fetch blockchains"))
            }
            
            guard let blockchainID = party.blockchain.split(separator: ".").first else {
                return reject(SwapSDKError.msg("cannot get blockchainID"))
            }
                        
            guard let blockchain = blockchains.blockchain(id: String(blockchainID)) else {
                return reject(SwapSDKError.msg("cannot get blockchain"))
            }
                        
            party.swap = self
            
            debug("\(party.id) Paying invoice on \(blockchainID)")
            
            blockchain.payInvoice(party: party).then { _ in
                resolve(())
            }.catch { error in
                reject(error)
            }
        }
    }
    
    public func settleInvoice() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            guard let blockchains = sdk?.blockchains else {
                return reject(SwapSDKError.msg("Cannot fetch blockchains"))
            }
            
            guard let blockchainID = counterparty.blockchain.split(separator: ".").first else {
                return reject(SwapSDKError.msg("cannot get blockchainID"))
            }
            
            guard let blockchain = blockchains.blockchain(id: String(blockchainID)) else {
                return reject(SwapSDKError.msg("cannot get blockchain"))
            }
            
            guard let store = sdk?.store else {
                return reject(SwapSDKError.msg("cannot get store"))
            }
            
            guard let secretHash = secretHash else {
                return reject(SwapSDKError.msg("cannot get store"))
            }
            
            do {
                guard let secret = try store.get(.secrets, secretHash)["secret"] as? Data else {
                    return reject(SwapSDKError.msg("Failed to fetch secret from store"))
                }
            
                debug("settling invoice for \(party.id)")
                
                blockchain.settleInvoice(party: counterparty, secret: secret).then { reciep in
                    self.party.receip = reciep
                    self.status = "\(self.partyType).invoice.settled"
                    self.emit(event: self.status, args: [self])
                    resolve(())
                }
            } catch {
                return reject(SwapSDKError.msg("Fetching secret error: \(error)"))
            }
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, secretHash, secretHolder, secretSeeker, status
    }
}

extension Swap {
    public func toJSON() -> [String: Any] {
        Utils.convertToJSON(self) ?? [:]
    }
    
    static func from(json: [String: Any]) throws -> Swap {
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        return try JSONDecoder().decode(Swap.self, from: jsonData)
    }
}
