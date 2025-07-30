import Foundation
import BigInt
import Web3
import Web3ContractABI

enum LiquidityError: Error, LocalizedError {
    case zeroNativeAmount
    case mismatchedId(expected: String, actual: String)
    
    var errorDescription: String? {
        switch self {
        case .zeroNativeAmount:
            return "nativeAmount cannot be 0!"
        case .mismatchedId(let expected, let actual):
            return "Invalid liquidity! Expected \(expected); got \(actual)!"
        }
    }
}

public final class Liquidity: Codable {
    var id: String?
    let ts: BigUInt?
    let chain: String
    let symbol: String
    let contractAddress: String
    let nativeAmount: BigInt
    let portalAmount: BigInt
    let nativeAddress: String
    let portalAddress: String
    var nativeReceipt: Receipt?
    var portalReceipt: Receipt?
    
    var isDeposit: Bool { nativeAmount > 0 }
    var isWithdrawal: Bool { nativeAmount < 0 }
    
    public var notifiebleId: String {
        let components = [
            nativeAddress,
            portalAddress.lowercased(),
            symbol,
            chain,
            contractAddress,
            abs(nativeAmount).description,
            abs(portalAmount).description
        ].joined(separator: "|")
        
        return components.sha256()
    }

    init(
        id: String? = nil,
        ts: BigUInt? = nil,
        chain: String,
        symbol: String,
        contractAddress: String,
        nativeAmount: BigInt,
        nativeAddress: String,
        portalAddress: String
    ) throws {
        guard nativeAmount != 0 else {
            throw LiquidityError.zeroNativeAmount
        }

        self.id = id ?? "0x" + String(repeating: "0", count: 64)
        self.ts = ts ?? BigUInt(Date().timeIntervalSince1970)
        self.chain = chain
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.nativeAmount = nativeAmount
        self.portalAmount = nativeAmount * 100
        self.nativeAddress = nativeAddress
        self.portalAddress = portalAddress
    }

    func equals(_ other: Liquidity) -> Bool {
        self.notifiebleId == other.notifiebleId
    }

    func toJSON() throws -> String {
        let json: [String: String] = [
            "id": "0x" + id!,
            "ts": ts!.description,
            "chain": chain,
            "symbol": symbol,
            "contractAddress": contractAddress,
            "nativeAmount": nativeAmount.description,
            "portalAmount": portalAmount.description,
            "nativeAddress": nativeAddress,
            "portalAddress": portalAddress,
            "nativeReceipt": nativeReceipt ?? "",
            "portalReceipt": portalReceipt ?? ""
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(json)
        
        return String(data: data, encoding: .utf8)!
    }

    public static func fromJSON(_ json: String) throws -> Liquidity {
        let cleanJson = json.replacingOccurrences(of: "^[^\\{]*|[^\\}]*$", with: "", options: .regularExpression)
        let decoder = JSONDecoder()
        return try decoder.decode(Liquidity.self, from: cleanJson.data(using: .utf8)!)
    }

    enum CodingKeys: String, CodingKey {
        case id, ts, chain, symbol, contractAddress, nativeAmount, portalAmount, nativeAddress, portalAddress
        case nativeReceipt, portalReceipt
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        if let tsString = try? container.decode(String.self, forKey: .ts) {
            ts = BigUInt(tsString) ?? BigUInt(0)
        } else {
            let tsInt = try container.decode(Int.self, forKey: .ts)
            ts = BigUInt(tsInt)
        }
        
        chain = try container.decode(String.self, forKey: .chain)
        symbol = try container.decode(String.self, forKey: .symbol)
        contractAddress = try container.decode(String.self, forKey: .contractAddress)
        
        let nativeAmountString = try container.decode(String.self, forKey: .nativeAmount)
        nativeAmount = BigInt(nativeAmountString) ?? BigInt(0)
        
        let portalAmountString = try container.decode(String.self, forKey: .portalAmount)
        portalAmount = BigInt(portalAmountString) ?? BigInt(0)
        
        nativeAddress = try container.decode(String.self, forKey: .nativeAddress)
        portalAddress = try container.decode(String.self, forKey: .portalAddress)
        portalReceipt = try container.decodeIfPresent(Receipt.self, forKey: .portalReceipt)
        nativeReceipt = try container.decodeIfPresent(Receipt.self, forKey: .nativeReceipt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ts, forKey: .ts)
        try container.encode(chain, forKey: .chain)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(contractAddress, forKey: .contractAddress)
        try container.encode(nativeAmount.hexSignedString(), forKey: .nativeAmount)
        try container.encode(portalAmount.hexSignedString(), forKey: .portalAmount)
        try container.encode(nativeAddress, forKey: .nativeAddress)
        try container.encode(portalAddress, forKey: .portalAddress)
        try container.encodeIfPresent(nativeReceipt, forKey: .nativeReceipt)
        try container.encodeIfPresent(portalReceipt, forKey: .portalReceipt)
    }

    func toSolidityTuple() -> SolidityTuple {
        let idData = Data(hex: self.id!)
        let tsValue = ts!
        let portalEthAddress = EthereumAddress(hexString: self.portalAddress)!

        return SolidityTuple(
            SolidityWrappedValue(value: idData, type: .bytes(length: 32)),
            SolidityWrappedValue(value: tsValue, type: .uint256),
            SolidityWrappedValue(value: nativeAmount, type: .int256),
            SolidityWrappedValue(value: portalAmount, type: .int256),
            SolidityWrappedValue(value: portalEthAddress, type: .address),
            SolidityWrappedValue(value: chain, type: .string),
            SolidityWrappedValue(value: symbol, type: .string),
            SolidityWrappedValue(value: contractAddress, type: .string),
            SolidityWrappedValue(value: nativeAddress, type: .string)
        )
    }

    static func fromSolidityValues(_ values: [Any]) -> Liquidity? {
        guard
            values.count == 9,
            let id = values[0] as? Data,
            let ts = values[1] as? BigUInt,
            let nativeAmount = values[2] as? BigInt,
            let portalAddress = values[4] as? EthereumAddress,
            let chain = values[5] as? String,
            let symbol = values[6] as? String,
            let contractAddress = values[7] as? String,
            let nativeAddress = values[8] as? String
        else {
            return nil
        }

        do {
            return try Liquidity(
                id: id.toHexString(),
                ts: ts,
                chain: chain,
                symbol: symbol,
                contractAddress: contractAddress,
                nativeAmount: BigInt(nativeAmount),
                nativeAddress: nativeAddress,
                portalAddress: portalAddress.hex(eip55: false)
            )
        } catch {
            return nil
        }
    }
}

private extension BigInt {
    func hexSignedString() -> String {
        let prefix = self.sign == .minus ? "-" : "+"
        return prefix + self.magnitude.serialize().map { String(format: "%02x", $0) }.joined()
    }

    init(fromSignedHexString string: String) throws {
        guard let signChar = string.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing sign"))
        }
        let hex = String(string.dropFirst())
        guard let magnitude = BigUInt(hex, radix: 16) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid hex"))
        }
        self.init(signChar == "-" ? -BigInt(magnitude) : BigInt(magnitude))
    }
}
