import Foundation
import Web3
import Web3ContractABI
import BigInt

protocol IPortalTransferContract: EthereumContract {
    func transfer(dstChain: String, receiver: EthereumAddress, amount: String, dstContract: EthereumAddress, message: Data) -> SolidityInvocation
}

open class PortalTransferContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    
    open var constructor: SolidityConstructor? = nil
    
    open var events: [SolidityEvent] {
        []
    }
    
    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension PortalTransferContract: IPortalTransferContract {
    func transfer(dstChain: String, receiver: EthereumAddress, amount: String, dstContract: EthereumAddress, message: Data) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "dstChain", type: .string),
            SolidityFunctionParameter(name: "receiver", type: .address),
            SolidityFunctionParameter(name: "amount", type: .string),
            SolidityFunctionParameter(name: "dstContract", type: .address),
            SolidityFunctionParameter(name: "message", type: .bytes(length: nil))
        ]
        
        let outputs = [
            SolidityFunctionParameter(name: "success", type: .bool)
        ]
        
        let method = SolidityNonPayableFunction(name: "portalTransfer", inputs: inputs, outputs: outputs, handler: self)
        
        return method.invoke(
            dstChain,
            receiver,
            amount,
            dstContract,
            message
        )
    }
}
