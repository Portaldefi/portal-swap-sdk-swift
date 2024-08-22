import Foundation
import Web3
import Web3ContractABI

protocol IAssetManagementContract: EthereumContract {
    func listAssets() -> SolidityInvocation
    func retrieveAsset(id: EthereumAddress) -> SolidityInvocation
    func retrieveAssetByNativeProps(blockchainName: String, blockchainAddress: String) -> SolidityInvocation
}

open class AssetManagementContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {[]}

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension AssetManagementContract: IAssetManagementContract {
    func listAssets() -> SolidityInvocation {
        let returnTypes: [SolidityType] = [.address, .string, .string, .string, .uint256, .string, .string, .uint8]
        let outputs = [SolidityFunctionParameter(name: "", type: .array(type: .tuple(returnTypes), length: nil))]
        let method = SolidityConstantFunction(name: "listAssets", outputs: outputs, handler: self)
        return method.invoke()
    }
    
    func retrieveAssetByNativeProps(blockchainName: String, blockchainAddress: String) -> SolidityInvocation {
        let returnTypes: [SolidityType] = [.address, .string, .string, .string, .uint256, .string, .string, .uint8]
        let outputs = [SolidityFunctionParameter(name: "", type: .tuple(returnTypes))]
        let method = SolidityConstantFunction(name: "retrieveAssetByNativeProps", outputs: outputs, handler: self)
        return method.invoke(blockchainName, blockchainAddress)
    }
    
    func retrieveAsset(id: EthereumAddress) -> SolidityInvocation {
        let returnTypes: [SolidityType] = [.address, .string, .string, .string, .uint256, .string, .string, .uint8]
        let outputs = [SolidityFunctionParameter(name: "", type: .tuple(returnTypes))]
        let method = SolidityConstantFunction(name: "retrieveAsset", outputs: outputs, handler: self)
        return method.invoke(id)
    }
}
