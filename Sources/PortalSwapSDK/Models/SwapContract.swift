import Web3
import Web3ContractABI
import Foundation

open class SwapContract: StaticContract, ISwapContract {
    public var address: EthereumAddress?
    public let eth: Web3.Eth

    open var constructor: SolidityConstructor?

    open var events: [SolidityEvent] {
        [SwapContract.InvoiceCreated, SwapContract.InvoicePaid, SwapContract.InvoiceSettled]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

public extension SwapContract {    
    static var InvoiceCreated: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "id", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "swap", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "payee", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "asset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "quantity", type: .uint256, indexed: false)
        ]
        return SolidityEvent(name: "InvoiceCreated", anonymous: false, inputs: inputs)
    }

    static var InvoicePaid: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "id", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "swap", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "payer", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "asset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "quantity", type: .uint256, indexed: false)
        ]
        return SolidityEvent(name: "InvoicePaid", anonymous: false, inputs: inputs)
    }

    static var InvoiceSettled: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "id", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "swap", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "payer", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "payee", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "asset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "quantity", type: .uint256, indexed: false),
            SolidityEvent.Parameter(name: "secret", type: .bytes(length: 32), indexed: false),
        ]
        return SolidityEvent(name: "InvoiceSettled", anonymous: false, inputs: inputs)
    }

    func createInvoice(id: Data, swap: Data, asset: EthereumAddress, quantity: BigUInt) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "swap", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "asset", type: .address),
            SolidityFunctionParameter(name: "quantity", type: .uint256)
        ]
        let method = SolidityNonPayableFunction(name: "createInvoice", inputs: inputs, handler: self)
        return method.invoke(id, swap, asset, quantity)
    }

    func payInvoice(id: Data, swap: Data, asset: EthereumAddress, quantity: BigUInt) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "swap", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "asset", type: .address),
            SolidityFunctionParameter(name: "quantity", type: .uint256)
        ]
        let method = SolidityPayableFunction(name: "payInvoice", inputs: inputs, handler: self)
        return method.invoke(id, swap, asset, quantity)
    }

    func settleInvoice(secret: Data, swap: Data) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "secret", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "swap", type: .bytes(length: 32))
        ]
        let method = SolidityPayableFunction(name: "settleInvoice", inputs: inputs, handler: self)
        return method.invoke(secret, swap)
    }
}
