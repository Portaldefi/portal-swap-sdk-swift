import Foundation
import Web3
import Web3ContractABI

enum AssetError: Error, LocalizedError {
    case invalidId(expected: String, got: String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidId(expected, got):
            return "Invalid asset! Expected \(expected); got \(got)!"
        case .decodingError(let error):
            return "Decoding error: \(error)"
        }
    }
}

struct Asset: CustomDebugStringConvertible {
    let id: String
    let name: String
    let chain: String
    let symbol: String
    let contractAddress: String
    let decimals: Int

    init(id: String, name: String, chain: String, symbol: String, contractAddress: String, decimals: Int) throws {
        let hasedId = Utils.sha256([chain, symbol, contractAddress])
        
        if hasedId.dropFirst(2) != id {
            throw AssetError.invalidId(expected: hasedId, got: id)
        }

        self.id = id
        self.name = name
        self.chain = chain
        self.symbol = symbol
        self.contractAddress = contractAddress
        self.decimals = decimals
    }

    var nativeAddress: String {
        contractAddress
    }

    var debugDescription: String {
        """
        Asset(
          id: \(id),
          name: \(name),
          chain: \(chain),
          symbol: \(symbol),
          contractAddress: \(contractAddress),
          decimals: \(decimals)
        )
        """
    }
}

extension Asset {
    func toSolidityTuple() -> SolidityTuple {
        // Convert id from String to Data
        let idData = Data(hex: self.id)
        
        return SolidityTuple(
            SolidityWrappedValue(value: idData, type: .bytes(length: 32)),
            SolidityWrappedValue(value: UInt8(self.decimals), type: .uint8),
            SolidityWrappedValue(value: self.name, type: .string),
            SolidityWrappedValue(value: self.chain, type: .string),
            SolidityWrappedValue(value: self.symbol, type: .string),
            SolidityWrappedValue(value: self.contractAddress, type: .string)
        )
    }
    
    static func fromSolidityValues(_ response: [String: Any]) throws -> Asset {
        guard
            let values = response[""] as? [Any],
            let id = values[0] as? Data,
            let decimals = values[1] as? UInt8,
            let name = values[2] as? String,
            let chain = values[3] as? String,
            let symbol = values[4] as? String,
            let contractAddress = values[5] as? String
        else {
            throw AssetError.decodingError("Invalid asset response format")
        }
        
        let idString = id.toHexString()
        
        return try Asset(
            id: idString,
            name: name,
            chain: chain,
            symbol: symbol,
            contractAddress: contractAddress,
            decimals: Int(decimals)
        )
    }
}
