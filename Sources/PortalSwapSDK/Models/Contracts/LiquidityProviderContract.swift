import Foundation
import Web3
import Web3ContractABI

protocol ILiquidityProviderContract: EthereumContract {
    static var InvoiceCreated: SolidityEvent { get }
    static var InvoiceSettled: SolidityEvent { get }
    func settle(secret: Data, swapId: Data) -> SolidityInvocation
}

open class LiquidityProvider: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {
        [LiquidityProvider.InvoiceCreated]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension LiquidityProvider: ILiquidityProviderContract {
    static var InvoiceCreated: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "swapId", type: .bytes(length: 32), indexed: false),
            SolidityEvent.Parameter(name: "swapOwner", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "counterParty", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "sellAsset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "sellAmount", type: .uint256, indexed: false)
        ]
        return SolidityEvent(name: "InvoiceCreated", anonymous: false, inputs: inputs)
    }
    
    static var InvoiceSettled: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "swapId", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "secret", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "counterParty", type: .address, indexed: true),
            SolidityEvent.Parameter(name: "sellAsset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "sellAmount", type: .uint256, indexed: false)
        ]
        return SolidityEvent(name: "InvoiceSettled", anonymous: false, inputs: inputs)
    }
    
    func settle(secret: Data, swapId: Data) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "secret", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "swapId", type: .bytes(length: 32))
        ]
        
        let method = SolidityNonPayableFunction(name: "settleInvoice", inputs: inputs, handler: self)
        return method.invoke(secret, swapId)
    }
}
