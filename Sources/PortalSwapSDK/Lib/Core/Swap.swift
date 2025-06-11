import Foundation
import Web3
import Web3ContractABI
import CryptoKit

public enum SwapState: Int16, Codable {
    case matched = 0
    case holderInvoiced
    case seekerInvoiced
    case holderPaid
    case seekerPaid
    case holderSettled
    case seekerSettled
}

typealias Invoice = String
typealias Receipt = String

protocol SwapDiff {
    var id: String { get }
    var state: SwapState { get }
}

struct PartyBase {
    let portalAddress: EthereumAddress
    let chain: String
    let symbol: String
    let contractAddress: String
    let amount: BigUInt
}

struct InvoiceHolder {
    let invoice: Invoice
}

struct MatchedSwap: SwapDiff {
    let id: String
    let state: SwapState = .matched
    let secretHash: String
    let secretHolder: PartyBase
    let secretSeeker: PartyBase
}

struct HolderInvoicedSwap: SwapDiff {
    let id: String
    let state: SwapState = .holderInvoiced
    let secretHash: String
    let secretSeeker: InvoiceHolder
}

struct SeekerInvoicedSwap: SwapDiff {
    let id: String
    let state: SwapState = .seekerInvoiced
    let secretHolder: InvoiceHolder
}

struct HolderPaidSwap: SwapDiff {
    let id: String
    let state: SwapState = .holderPaid
    let secretHolder: Receipt
}

struct SeekerPaidSwap: SwapDiff {
    let id: String
    let state: SwapState = .seekerPaid
    let secretSeeker: Receipt
}

struct HolderSettledSwap: SwapDiff {
    let id: String
    let state: SwapState = .holderSettled
    let secret: Data
}

struct SeekerSettledSwap: SwapDiff {
    let id: String
    let state: SwapState = .seekerSettled
}

public final class Swap {
    let NULL_HASH: String = "0x" + String(repeating: "0", count: 64)
    
    private(set) var secret: Data?

    var secretValue: Data? {
        return secret
    }
    
    static let VALID_SWAP_TRANSITIONS: [SwapState: [SwapState]] = [
        .matched: [.holderInvoiced],
        .holderInvoiced: [.seekerInvoiced],
        .seekerInvoiced: [.holderPaid],
        .holderPaid: [.seekerPaid],
        .seekerPaid: [.holderSettled],
        .holderSettled: [.seekerSettled],
        .seekerSettled: []
    ]

    public let id: String
    
    private(set) var state: SwapState
    var secretHash: String
    
    var secretHolder: Party
    var secretSeeker: Party

    enum CodingKeys: String, CodingKey {
        case id, state, secretHash, secretHolder, secretSeeker
    }

    init(json: [String: Any]) throws {
        guard
            let swap = json["swap"] as? [Any],
            swap.count == 5,
            let id = swap[0] as? Data,
            let state = swap[1] as? UInt8,
            let secretHash = swap[2] as? Data,
            let secretHolder = swap[3] as? [Any], secretHolder.count == 7,
            let secretSeeker = swap[4] as? [Any], secretSeeker.count == 7,
            let holderAddress = secretHolder[0] as? EthereumAddress,
            let holderAmount = secretHolder[1] as? BigUInt,
            let holderChain = secretHolder[2] as? String,
            let holderSymbol = secretHolder[3] as? String,
            let holderContractAddress = secretHolder[4] as? String,
            let holderInvoice = secretHolder[5] as? String,
            let holderReceipt = secretHolder[6] as? String,
            let seekerAddress = secretSeeker[0] as? EthereumAddress,
            let seekerAmount = secretSeeker[1] as? BigUInt,
            let seekerChain = secretSeeker[2] as? String,
            let seekerSymbol = secretSeeker[3] as? String,
            let seekerContractAddress = secretSeeker[4] as? String,
            let seekerInvoice = secretSeeker[5] as? String,
            let seekerReceipt = secretSeeker[6] as? String
        else {
            throw SdkError(message: "SwapMatched event decoding failed", code: String())
        }
        
        self.id = id.hexString
        
        guard let state = SwapState(rawValue: Int16(state)) else {
            throw SdkError(message: "Unknown state", code: String())
        }
        
        self.state = state
        self.secretHash = "0x" + secretHash.hexString
        
        self.secretHolder = Party(
            portalAddress: holderAddress,
            amount: holderAmount,
            chain: holderChain,
            symbol: holderSymbol,
            contractAddress: holderContractAddress,
            invoice: holderInvoice,
            receipt: holderReceipt
        )
        
        self.secretSeeker = Party(
            portalAddress: seekerAddress,
            amount: seekerAmount,
            chain: seekerChain,
            symbol: seekerSymbol,
            contractAddress: seekerContractAddress,
            invoice: seekerInvoice,
            receipt: seekerReceipt
        )
        
        self.secretHolder.swap = self
        self.secretSeeker.swap = self
    }
    
    init(record: DBSwap) throws {
        self.id = record.swapId!.hexString
        
        guard let state = SwapState(rawValue: record.state) else {
            throw SdkError(message: "Unknown state", code: String())
        }
        
        self.state = state
        self.secretHash = record.secretHash!.hexString
        
        let secretHolder = record.secretHolder!
        
        self.secretHolder = Party(
            portalAddress: try EthereumAddress(hex: secretHolder.portalAddress!, eip55: false),
            amount: BigUInt(stringLiteral: secretHolder.amount!),
            chain: secretHolder.chain!,
            symbol: secretHolder.symbol!,
            contractAddress: secretHolder.contractAddress!,
            invoice: secretHolder.invoice,
            receipt: secretHolder.receipt
        )
        
        let secretSeeker = record.secretSeeker!
        
        self.secretSeeker = Party(
            portalAddress: try EthereumAddress(hex: secretSeeker.portalAddress!, eip55: false),
            amount: BigUInt(stringLiteral: secretSeeker.amount!),
            chain: secretSeeker.chain!,
            symbol: secretSeeker.symbol!,
            contractAddress: secretSeeker.contractAddress!,
            invoice: secretSeeker.invoice,
            receipt: secretSeeker.receipt
        )
        
        self.secretHolder.swap = self
        self.secretSeeker.swap = self
    }
    
    func setSecret(_ newSecret: Data) throws {
        let secretHash = newSecret.sha256()
        if self.secretHash != secretHash.hexString {
            throw SdkError(message: "secretHash mismatch: \(self.secretHash) vs \(secretHash.hexString)", code: String())
        }
        self.secret = newSecret
    }

    func setSecretHash(_ newSecretHash: String) throws {
        guard secretHash == "0x0000000000000000000000000000000000000000000000000000000000000000" else {
            throw NSError(domain: "SwapError", code: 1, userInfo: [NSLocalizedDescriptionKey: "secretHash cannot be set more than once!"])
        }
        secretHash = newSecretHash.hasPrefix("0x") ? newSecretHash : "0x\(newSecretHash)"
    }

    func hasParty(_ portalAddress: String) -> Bool {
        [
            secretHolder.portalAddress.hex(eip55: false).lowercased(),
            secretSeeker.portalAddress.hex(eip55: false).lowercased()
        ]
        .contains(portalAddress.lowercased())
    }

    func isSecretHolder(_ portalAddress: String) -> Bool {
        secretHolder.portalAddress.hex(eip55: false).lowercased() == portalAddress.lowercased()
    }

    func isSecretSeeker(_ portalAddress: String) -> Bool {
        secretSeeker.portalAddress.hex(eip55: false).lowercased() == portalAddress.lowercased()
    }
    
    func update(_ diff: SwapDiff) throws {
        state = diff.state
        
        switch diff {
        case let holderInvoicedSwap as HolderInvoicedSwap:
            self.secretHash = holderInvoicedSwap.secretHash
            self.secretSeeker.invoice = holderInvoicedSwap.secretSeeker.invoice
            
        case let seekerInvoicedSwap as SeekerInvoicedSwap:
            self.secretHolder.invoice = seekerInvoicedSwap.secretHolder.invoice
            
        case let holderPaidSwap as HolderPaidSwap:
            self.secretHolder.receipt = holderPaidSwap.secretHolder
            
        case let seekerPaidSwap as SeekerPaidSwap:
            self.secretSeeker.receipt = seekerPaidSwap.secretSeeker
            
        case let holderSettledSwap as HolderSettledSwap:
            let secret = holderSettledSwap.secret
            let secretHash = secret.sha256()
            
            if Data(hex: self.secretHash) != secretHash {
                throw SdkError(message: "secretHash mismatch: \(self.secretHash) vs \(secretHash)", code: String())
            }
            
            self.secret = secret
            
        case _ as SeekerSettledSwap:
            break
            
        default:
            throw SdkError(message: "Invalid SwapDiff type for update", code: String())
        }
    }
    
    func updateFromSwap(_ swap: Swap) throws {
        state = swap.state
        
        switch swap.state {
        case .holderInvoiced:
            if swap.secretHash != self.secretHash {
                self.secretHash = swap.secretHash
            }
            if let invoice = swap.secretSeeker.invoice {
                self.secretSeeker.invoice = invoice
            }
            
        case .seekerInvoiced:
            if let invoice = swap.secretHolder.invoice {
                self.secretHolder.invoice = invoice
            }
            
        case .holderPaid:
            if let receipt = swap.secretHolder.receipt {
                self.secretHolder.receipt = receipt
            }
            
        case .seekerPaid:
            if let receipt = swap.secretSeeker.receipt {
                self.secretSeeker.receipt = receipt
            }
            
        case .holderSettled:
            if let secret = swap.secret {
                let secretHash = secret.sha256()
                
                if Data(hex: self.secretHash) != secretHash {
                    throw SdkError(message: "secretHash mismatch: \(self.secretHash) vs \(secretHash)", code: String())
                }
                
                self.secret = secret
            }
            
        default:
            break
        }
    }

    func setState(_ newState: SwapState) throws {
        guard let allowedTransitions = Swap.VALID_SWAP_TRANSITIONS[state],
              allowedTransitions.contains(newState) else {
            throw SdkError(message: "Invalid transition: \(state) → \(newState)", code: String())
        }
        state = newState
    }
    
    func toJSON() -> [String: Any] {
        let json: [String: Any] = [
            "id": id,
            "state": state.rawValue,
            "secretHash": secretHash,
            "secretHolder": [
                "portalAddress": secretHolder.portalAddress.hex(eip55: true),
                "chain": secretHolder.chain,
                "symbol": secretHolder.symbol,
                "contractAddress": secretHolder.contractAddress,
                "amount": secretHolder.amount.description,
                "invoice": secretHolder.invoice ?? "",
                "receipt": secretHolder.receipt ?? ""
            ] as [String: Any],
            "secretSeeker": [
                "portalAddress": secretSeeker.portalAddress.hex(eip55: true),
                "chain": secretSeeker.chain,
                "symbol": secretSeeker.symbol,
                "contractAddress": secretSeeker.contractAddress,
                "amount": secretSeeker.amount.description,
                "invoice": secretSeeker.invoice ?? "",
                "receipt": secretSeeker.receipt ?? ""
            ] as [String: Any]
        ]
        
        return json
    }
    
    static func == (lhs: Swap, rhs: Swap) -> Bool {
        lhs.id == rhs.id
    }
}
