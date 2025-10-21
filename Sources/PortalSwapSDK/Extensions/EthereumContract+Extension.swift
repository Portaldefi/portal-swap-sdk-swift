import Foundation
import Web3
import Web3ContractABI

extension DynamicContract {
    static func contractAbiData(abi: String) throws -> Data {
        guard let abiData = abi.data(using: .utf8) else {
            throw SwapSDKError.msg("Failed to convert contract ABI to Data.")
        }

        let jsonObject = try JSONSerialization.jsonObject(with: abiData, options: [])
        
        guard let abiDict = jsonObject as? [String: Any] else {
            throw SwapSDKError.msg("Contract ABI is not a valid [String: Any] dictionary.")
        }
        
        let abiArray = abiDict["abi"] as! [[String: Any]]

        let filteredAbiArray = abiArray.filter { item in
            guard let t = item["type"] as? String else { return false }
            return t != "receive" && t != "error"
        }
        
        return try JSONSerialization.data(withJSONObject: filteredAbiArray, options: [])
    }
    
    static func topics(contract: DynamicContract) throws -> [EthereumData] {
        var topics: [EthereumData] = []
        
        for (_, event) in contract.events.enumerated() {
            print(event.name)
            let signatureHex = "0x\(Utils.keccak256Hash(of: event.signature))"
            print("event signature: \(signatureHex)")
            let data = try EthereumData(ethereumValue: signatureHex)
            topics.append(data)
        }
        
        return topics
    }
    
    static func address(_ address: String?) throws -> EthereumAddress {
        guard let address else {
            throw SwapSDKError.msg("Ethereum cannot prepare contract")
        }
                
        let addresisEipp55 = Utils.isEIP55Compliant(address: address)
        return try EthereumAddress(hex: address, eip55: addresisEipp55)
    }
}
