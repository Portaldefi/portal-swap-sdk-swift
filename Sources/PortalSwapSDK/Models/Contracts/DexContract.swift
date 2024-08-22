import Web3
import Web3ContractABI
import Foundation

protocol IDexContract: EthereumContract {
    static var OrderCreated: SolidityEvent { get }
    func swapOrder(secretHash: Data, sellAsset: EthereumAddress, sellAmount: BigUInt, swapOwner: EthereumAddress) -> SolidityInvocation
}


open class DexContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?

    open var events: [SolidityEvent] {
        [DexContract.OrderCreated]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension DexContract: IDexContract {
    static var OrderCreated: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "secretHash", type: .bytes(length: 32), indexed: false),
            SolidityEvent.Parameter(name: "sellAsset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "sellAmount", type: .uint256, indexed: false),
            SolidityEvent.Parameter(name: "swapOwner", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "swapId", type: .bytes(length: 32), indexed: false),
            SolidityEvent.Parameter(name: "swapCreation", type: .uint256, indexed: false)
        ]
        return SolidityEvent(name: "OrderCreated", anonymous: false, inputs: inputs)
    }
    
    func swapOrder(secretHash: Data, sellAsset: EthereumAddress, sellAmount: BigUInt, swapOwner: EthereumAddress) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "secretHash", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "sellAsset", type: .address),
            SolidityFunctionParameter(name: "sellAmount", type: .uint),
            SolidityFunctionParameter(name: "swapOwner", type: .address)
        ]

        let method = SolidityPayableFunction(name: "swapOrder", inputs: inputs, handler: self)
        return method.invoke(secretHash, sellAsset, sellAmount, swapOwner)
    }
}
