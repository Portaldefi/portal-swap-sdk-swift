import Foundation
import Web3
import Web3ContractABI

protocol IAdmmContract: EthereumContract {
    static var SwapCreated: SolidityEvent { get }
}

open class ADMMContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {
        [ADMMContract.SwapCreated]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension ADMMContract: IAdmmContract {
    static var SwapCreated: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "swap", type: .tuple(
                [
                    .bytes(length: 32),
                    .bytes(length: 32),
                    .bytes(length: 32),
                    .address,
                    .uint256,
                    .address,
                    .uint256,
                    .uint256,
                    .uint256,
                    .address,
                    .string
                ]
            ), indexed: false)
        ]
        
        return SolidityEvent(name: "SwapCreated", anonymous: false, inputs: inputs)
    }
}
