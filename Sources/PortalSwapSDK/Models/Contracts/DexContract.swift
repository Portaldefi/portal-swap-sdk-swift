import Web3
import Web3ContractABI
import Foundation

protocol IDexContract: EthereumContract {
    static var Authorized: SolidityEvent { get }
    static var OrderCreated: SolidityEvent { get }
    func createInvoice(id: Data, swapId: Data, asset: EthereumAddress, quantity: BigUInt) -> SolidityInvocation
    func swapOrder(secretHash: Data, sellAsset: EthereumAddress, sellAmount: BigUInt, swapOwner: EthereumAddress) -> SolidityInvocation
    func feePercentage() -> SolidityInvocation
    func authorize(swapId: Data, withdrawals: [AuthorizedWithdrawal]) -> SolidityInvocation
}

struct AuthorizedWithdrawal {
    let addr: EthereumAddress
    let amount: BigUInt
}

open class DexContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?

    open var events: [SolidityEvent] {
        [DexContract.OrderCreated, DexContract.Authorized]
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
    
    static var Authorized: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "swapId", type: .bytes(length: 32), indexed: false)
        ]
        return SolidityEvent(name: "Authorized", anonymous: false, inputs: inputs)
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
    
    func createInvoice(id: Data, swapId: Data, asset: EthereumAddress, quantity: BigUInt) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "swapId", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "asset", type: .address),
            SolidityFunctionParameter(name: "quantity", type: .uint256)
        ]
        
        let method = SolidityPayableFunction(name: "createInvoice", inputs: inputs, handler: self)
        return method.invoke(id, swapId, asset, quantity)
    }
    
    func feePercentage() -> SolidityInvocation {
        let outputs = [SolidityFunctionParameter(name: "", type: .uint256)]
        let method = SolidityConstantFunction(name: "feePercentage", outputs: outputs, handler: self)
        return method.invoke()
    }
    
    func authorize(swapId: Data, withdrawals: [AuthorizedWithdrawal]) -> SolidityInvocation {
        let method = SolidityNonPayableFunction(
            name: "authorize",
            inputs: [
                SolidityFunctionParameter(name: "swapId", type: .bytes(length: 32)),
                SolidityFunctionParameter(name: "withdraws", type: .array(type: .tuple([.address, .uint256]), length: nil))
            ],
            handler: self
        )
        
        let _withdrawals = withdrawals.map { w in
            SolidityTuple(
                SolidityWrappedValue(value: w.addr, type: .address),
                SolidityWrappedValue(value: w.amount, type: .uint256)
            )
        }
        
        return method.invoke(swapId, _withdrawals)
    }
}
