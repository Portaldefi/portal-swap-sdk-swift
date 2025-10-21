import Foundation
import Web3
import Web3ContractABI

protocol IAssetManagerContract: EthereumContract {
    func retrieveAssets() -> SolidityInvocation
    func retrieveAsset(id: Data) -> SolidityInvocation
    func retrieveAsset(chain: String, symbol: String) -> SolidityInvocation
    func assetIdByProps(chain: String, symbol: String) -> SolidityInvocation
}

open class AssetManagerContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor? = nil
    open var events: [SolidityEvent] { return [] }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension AssetManagerContract: IAssetManagerContract {
    func retrieveAssets() -> SolidityInvocation {
        let returnTypes: [SolidityType] = [
            .bytes(length: 32), .uint8, .bool, .string, .string, .string, .string
        ]
        let outputs = [
            SolidityFunctionParameter(name: "", type: .array(type: .tuple(returnTypes), length: nil))
        ]
        let method = SolidityConstantFunction(name: "retrieveAssets", outputs: outputs, handler: self)
        return method.invoke()
    }
    
    func retrieveAsset(id: Data) -> SolidityInvocation {
        let returnTypes: [SolidityType] = [
            .bytes(length: 32), .uint8, .string, .string, .string, .string
        ]
        let inputs = [SolidityFunctionParameter(name: "assetId", type: .bytes(length: 32))]
        let outputs = [SolidityFunctionParameter(name: "", type: .tuple(returnTypes))]
        let method = SolidityConstantFunction(name: "retrieveAsset", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(id)
    }
    
    func retrieveAsset(chain: String, symbol: String) -> SolidityInvocation {
        let returnTypes: [SolidityType] = [
            .bytes(length: 32), // id
            .uint8,             // decimals
            .bool,              // isEnabled
            .string,            // name
            .string,            // chain
            .string,            // symbol
            .string             // contractAddress
        ]
        let inputs = [
            SolidityFunctionParameter(name: "chain", type: .string),
            SolidityFunctionParameter(name: "symbol", type: .string)
        ]
        let outputs = [SolidityFunctionParameter(name: "", type: .tuple(returnTypes))]
        let method = SolidityConstantFunction(name: "retrieveAsset", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(chain, symbol)
    }
    
    func assetIdByProps(chain: String, symbol: String) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "chain", type: .string),
            SolidityFunctionParameter(name: "symbol", type: .string)
        ]
        let outputs = [SolidityFunctionParameter(name: "", type: .bytes(length: 32))]
        let method = SolidityConstantFunction(name: "_assetIdByProps", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(chain, symbol)
    }
}
