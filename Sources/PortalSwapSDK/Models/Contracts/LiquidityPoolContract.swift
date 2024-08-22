import Foundation
import Web3
import Web3ContractABI

protocol ILiquidityPoolContract: EthereumContract {
    func listPools() -> SolidityInvocation
}

open class LiquidityPoolContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {[]}

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension LiquidityPoolContract: ILiquidityPoolContract {
    func listPools() -> SolidityInvocation {
        let returnTypes: [SolidityType] = [.bytes(length: 32), .address, .address, .uint256, .uint256, .uint256]
        let outputs = [SolidityFunctionParameter(name: "", type: .array(type: .tuple(returnTypes), length: nil))]
        let method = SolidityConstantFunction(name: "listPools", outputs: outputs, handler: self)
        return method.invoke()
    }
}
