import Foundation
import Web3
import Web3ContractABI

protocol IAdmmContract: EthereumContract {
    static var SwapCreated: SolidityEvent { get }
    static var SwapValidated: SolidityEvent { get }
    static var SwapMatched: SolidityEvent { get }
    static var InvoiceRegistered: SolidityEvent { get }
    
    func registerInvoice(id: Data, secretHash: Data, amount: BigUInt, invoice: String) -> SolidityInvocation
    func createSwap(id: Data, liquidityPoolId: Data, secretHash: Data, sellAsset: EthereumAddress, sellAmount: BigUInt, buyAsset: EthereumAddress, buyAmount: BigUInt, slippage: BigUInt, swapCreation: BigUInt, swapOwner: EthereumAddress, buyId: String, status: String) -> SolidityInvocation
    func getSwap(id: Data) -> SolidityInvocation
    func eventOutputs(id: Data) -> SolidityInvocation
    
}

open class ADMMContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    
    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {
        [
            ADMMContract.SwapCreated,
            ADMMContract.SwapValidated,
            ADMMContract.SwapMatched,
            ADMMContract.InvoiceRegistered
        ]
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
                    .string,
                    .string
                ]
            ), indexed: false)
        ]
        
        return SolidityEvent(name: "SwapCreated", anonymous: false, inputs: inputs)
    }
    
    static var SwapValidated: SolidityEvent {
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
                    .string,
                    .string
                ]
            ), indexed: false)
        ]
        
        return SolidityEvent(name: "SwapValidated", anonymous: false, inputs: inputs)
    }
    
    static var SwapMatched: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "id", type: .bytes(length: 32), indexed: true),
            SolidityEvent.Parameter(name: "liquidityOwner", type: .address, indexed: true),
            SolidityEvent.Parameter(name: "sellAsset", type: .address, indexed: false),
            SolidityEvent.Parameter(name: "matchedSellAmount", type: .uint256, indexed: false),
            SolidityEvent.Parameter(name: "matchedBuyAmount", type: .uint256, indexed: false)
        ]
        
        return SolidityEvent(name: "SwapMatched", anonymous: false, inputs: inputs)
    }
    
    static var InvoiceRegistered: SolidityEvent {
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "invoice", type: .tuple(
                [
                    .bytes(length: 32),
                    .bytes(length: 32),
                    .uint256,
                    .string
                ]
            ), indexed: false)
        ]
        
        return SolidityEvent(name: "InvoiceRegistered", anonymous: false, inputs: inputs)
    }
    
    func getSwap(id: Data) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32))
        ]
        let outputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "liquidityPoolId", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "secretHash", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "sellAsset", type: .address),
            SolidityFunctionParameter(name: "sellAmount", type: .uint256),
            SolidityFunctionParameter(name: "buyAsset", type: .address),
            SolidityFunctionParameter(name: "buyAmount", type: .uint256),
            SolidityFunctionParameter(name: "slippage", type: .uint256),
            SolidityFunctionParameter(name: "swapCreation", type: .uint256),
            SolidityFunctionParameter(name: "swapOwner", type: .address),
            SolidityFunctionParameter(name: "buyId", type: .string),
            SolidityFunctionParameter(name: "status", type: .string)
        ]
        let method = SolidityConstantFunction(name: "swaps", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(id)
    }
    
    func eventOutputs(id: Data) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32))
        ]
        let outputs = [
            SolidityFunctionParameter(name: "id", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "secretHash", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "matchedLp", type: .address),
            SolidityFunctionParameter(name: "matchedSellAmount", type: .uint256),
            SolidityFunctionParameter(name: "matchedBuyAmount", type: .uint256),
            SolidityFunctionParameter(name: "invoice", type: .string)
        ]
        let method = SolidityConstantFunction(name: "eventOutputs", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(id)
    }
    
    func registerInvoice(id: Data, secretHash: Data, amount: BigUInt, invoice: String) -> SolidityInvocation {
        let inputTypes: [SolidityType] = [
            .bytes(length: 32),
            .bytes(length: 32),
            .uint256,
            .string
        ]
        
        let inputs = [
            SolidityFunctionParameter(name: "invoice", type: .tuple(inputTypes))
        ]

        let method = SolidityNonPayableFunction(name: "registerInvoice", inputs: inputs, handler: self)
        
        let invoiceTuple = SolidityTuple(
            SolidityWrappedValue(value: id, type: .bytes(length: 32)),
            SolidityWrappedValue(value: secretHash, type: .bytes(length: 32)),
            SolidityWrappedValue(value: amount, type: .uint256),
            SolidityWrappedValue(value: invoice, type: .string)
        )
        
        return method.invoke(invoiceTuple)
    }
    
    func createSwap(id: Data, liquidityPoolId: Data, secretHash: Data, sellAsset: EthereumAddress, sellAmount: BigUInt, buyAsset: EthereumAddress, buyAmount: BigUInt, slippage: BigUInt, swapCreation: BigUInt, swapOwner: EthereumAddress, buyId: String, status: String) -> SolidityInvocation {
                
        let inputTypes: [SolidityType] = [
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
            .string,
            .string
        ]
        
        let inputs = [
            SolidityFunctionParameter(name: "swap", type: .tuple(inputTypes))
        ]
        
        let method = SolidityNonPayableFunction(name: "createSwap", inputs: inputs, handler: self)
        
        let swapTuple = SolidityTuple(
            SolidityWrappedValue(value: id, type: .bytes(length: 32)),
            SolidityWrappedValue(value: liquidityPoolId, type: .bytes(length: 32)),
            SolidityWrappedValue(value: secretHash, type: .bytes(length: 32)),
            SolidityWrappedValue(value: sellAsset, type: .address),
            SolidityWrappedValue(value: sellAmount, type: .uint256),
            SolidityWrappedValue(value: buyAsset, type: .address),
            SolidityWrappedValue(value: buyAmount, type: .uint256),
            SolidityWrappedValue(value: slippage, type: .uint256),
            SolidityWrappedValue(value: swapCreation, type: .uint256),
            SolidityWrappedValue(value: swapOwner, type: .address),
            SolidityWrappedValue(value: buyId, type: .string),
            SolidityWrappedValue(value: status, type: .string)
        )
        
        return method.invoke(swapTuple)
    }
}
