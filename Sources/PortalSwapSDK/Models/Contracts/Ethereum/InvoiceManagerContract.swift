import Foundation
import BigInt
import Web3
import Web3ContractABI

protocol IInvoiceManagerContract: EthereumContract, IRPCLogsPoller {
    static var Deposit: SolidityEvent { get }
    static var Withdraw: SolidityEvent { get }
    static var SwapInvoiceCreated: SolidityEvent { get }
    static var SwapHolderPaid: SolidityEvent { get }
    static var SwapHolderSettled: SolidityEvent { get }
    static var SwapSeekerPaid: SolidityEvent { get }
    static var SwapSeekerSettled: SolidityEvent { get }

    func createInvoice(swap: Swap) -> SolidityInvocation
    func payInvoice(swap: Swap) -> SolidityInvocation
    func settleInvoice(swap: Swap, secret: Data) -> SolidityInvocation
    func getSwapTimeout(swap swapId: String) -> SolidityInvocation
}

class InvoiceManagerContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    private var logPoller: RPCLogPoller?
    
    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {
        [
            InvoiceManagerContract.Deposit,
            InvoiceManagerContract.Withdraw,
            InvoiceManagerContract.SwapInvoiceCreated,
            InvoiceManagerContract.SwapHolderPaid,
            InvoiceManagerContract.SwapHolderSettled,
            InvoiceManagerContract.SwapSeekerPaid,
            InvoiceManagerContract.SwapSeekerSettled
        ]
    }
    
    private static let partyComponents: [SolidityType] = [
        .address, // portalAddress
        .uint256, // amount
        .string,  // chain
        .string,  // symbol
        .string,  // contractAddress
        .string,  // invoice
        .string   // receipt
    ]

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
    
    private static func swapTupleParam(named name: String) -> SolidityEvent.Parameter {
        return .init(
            name: name,
            type: .tuple([
                .bytes(length: 32),           // id
                .uint8,                       // state
                .bytes(length: 32),           // secretHash
                .tuple(partyComponents),      // secretHolder
                .tuple(partyComponents)       // secretSeeker
            ]),
            indexed: false
        )
    }
}

extension InvoiceManagerContract: IInvoiceManagerContract {
    static let Deposit = SolidityEvent(
        name: "Deposit",
        anonymous: false,
        inputs: [
            .init(name: "id", type: .bytes(length: 32),  indexed: false),
            .init(name: "ts", type: .uint256,  indexed: false),
            .init(name: "chain", type: .string,  indexed: false),
            .init(name: "symbol", type: .string,  indexed: false),
            .init(name: "contractAddress", type: .address, indexed: false),
            .init(name: "nativeAmount", type: .uint256, indexed: false),
            .init(name: "nativeAddress", type: .address, indexed: true),
            .init(name: "portalAddress", type: .address, indexed: true),
        ]
    )
    
    public static let SwapHolderPaid = SolidityEvent(
        name: "SwapHolderPaid",
        anonymous: false,
        inputs: [.init(name: "id", type: .bytes(length: 32), indexed: false)]
    )
    
    public static let SwapHolderSettled = SolidityEvent(
        name: "SwapHolderSettled",
        anonymous: false,
        inputs: [
            .init(name: "id", type: .bytes(length: 32), indexed: false),
            .init(name: "secret", type: .bytes(length: nil), indexed: false)
        ]
    )
    
    public static let SwapInvoiceCreated = SolidityEvent(
        name: "SwapInvoiceCreated",
        anonymous: false,
        inputs: [swapTupleParam(named: "swap")]
    )
    
    public static let SwapSeekerPaid = SolidityEvent(
        name: "SwapSeekerPaid",
        anonymous: false,
        inputs: [.init(name: "id", type: .bytes(length: 32), indexed: false)]
    )
    
    public static let SwapSeekerSettled = SolidityEvent(
        name: "SwapSeekerSettled",
        anonymous: false,
        inputs: [.init(name: "id", type: .bytes(length: 32), indexed: false)]
    )
    
    public static let Withdraw = SolidityEvent(
        name: "Withdraw",
        anonymous: false,
        inputs: [
            .init(name: "id", type: .bytes(length: 32),  indexed: false),
            .init(name: "ts", type: .uint256,  indexed: false),
            .init(name: "chain", type: .string,  indexed: false),
            .init(name: "symbol", type: .string,  indexed: false),
            .init(name: "contractAddress", type: .address, indexed: false),
            .init(name: "nativeAmount", type: .int256, indexed: false),
            .init(name: "nativeAddress", type: .address, indexed: true),
            .init(name: "portalAddress", type: .address, indexed: true),
        ]
    )
    
    func createInvoice(swap: Swap) -> SolidityInvocation {
        let secretHolder = SolidityTuple(
            SolidityWrappedValue(value: swap.secretHolder.portalAddress, type: .address),
            SolidityWrappedValue(value: swap.secretHolder.amount, type: .uint256),
            SolidityWrappedValue(value: swap.secretHolder.chain, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.symbol, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.contractAddress, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.invoice ?? String(), type: .string),
            SolidityWrappedValue(value: swap.secretHolder.receipt ?? String(), type: .string)
        )
        
        let secretSeeker = SolidityTuple(
            SolidityWrappedValue(value: swap.secretSeeker.portalAddress, type: .address),
            SolidityWrappedValue(value: swap.secretSeeker.amount, type: .uint256),
            SolidityWrappedValue(value: swap.secretSeeker.chain, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.symbol, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.contractAddress, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.invoice ?? String(), type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.receipt ?? String(), type: .string)
        )
        
        let partyType = SolidityType.tuple([
            .address, .uint256, .string, .string, .string, .string, .string
        ])
        
        let swapTuple = SolidityTuple(
            SolidityWrappedValue(value: Data(hex: swap.id), type: .bytes(length: 32)),
            SolidityWrappedValue(value: swap.state.rawValue, type: .uint8),
            SolidityWrappedValue(value: Data(hex: swap.secretHash), type: .bytes(length: 32)),
            SolidityWrappedValue(value: secretHolder, type: partyType),
            SolidityWrappedValue(value: secretSeeker, type: partyType)
        )
        
        let swapType = SolidityType.tuple([
            .bytes(length: 32),
            .uint8,
            .bytes(length: 32),
            partyType,
            partyType
        ])
        
        let inputs = [
            SolidityFunctionParameter(name: "swap", type: swapType)
        ]
        
        let method = SolidityNonPayableFunction(name: "createInvoice", inputs: inputs, handler: self)
        return method.invoke(swapTuple)
    }
    
    func payInvoice(swap: Swap) -> SolidityInvocation {
        let secretHolder = SolidityTuple(
            SolidityWrappedValue(value: swap.secretHolder.portalAddress, type: .address),
            SolidityWrappedValue(value: swap.secretHolder.amount, type: .uint256),
            SolidityWrappedValue(value: swap.secretHolder.chain, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.symbol, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.contractAddress, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.invoice ?? String(), type: .string),
            SolidityWrappedValue(value: swap.secretHolder.receipt ?? String(), type: .string)
        )
        
        let secretSeeker = SolidityTuple(
            SolidityWrappedValue(value: swap.secretSeeker.portalAddress, type: .address),
            SolidityWrappedValue(value: swap.secretSeeker.amount, type: .uint256),
            SolidityWrappedValue(value: swap.secretSeeker.chain, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.symbol, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.contractAddress, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.invoice ?? String(), type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.receipt ?? String(), type: .string)
        )
        
        let partyType = SolidityType.tuple([
            .address, .uint256, .string, .string, .string, .string, .string
        ])
        
        let swapTuple = SolidityTuple(
            SolidityWrappedValue(value: Data(hex: swap.id), type: .bytes(length: 32)),
            SolidityWrappedValue(value: swap.state.rawValue, type: .uint8),
            SolidityWrappedValue(value: Data(hex: swap.secretHash), type: .bytes(length: 32)),
            SolidityWrappedValue(value: secretHolder, type: partyType),
            SolidityWrappedValue(value: secretSeeker, type: partyType)
        )
        
        let swapType = SolidityType.tuple([
            .bytes(length: 32),
            .uint8,
            .bytes(length: 32),
            partyType,
            partyType
        ])
        
        let inputs = [
            SolidityFunctionParameter(name: "swap", type: swapType)
        ]
        
        let method = SolidityNonPayableFunction(name: "payInvoice", inputs: inputs, handler: self)
        return method.invoke(swapTuple)
    }
    
    func settleInvoice(swap: Swap, secret: Data) -> SolidityInvocation {
        let secretHolder = SolidityTuple(
            SolidityWrappedValue(value: swap.secretHolder.portalAddress, type: .address),
            SolidityWrappedValue(value: swap.secretHolder.amount, type: .uint256),
            SolidityWrappedValue(value: swap.secretHolder.chain, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.symbol, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.contractAddress, type: .string),
            SolidityWrappedValue(value: swap.secretHolder.invoice ?? String(), type: .string),
            SolidityWrappedValue(value: swap.secretHolder.receipt ?? String(), type: .string)
        )
        
        let secretSeeker = SolidityTuple(
            SolidityWrappedValue(value: swap.secretSeeker.portalAddress, type: .address),
            SolidityWrappedValue(value: swap.secretSeeker.amount, type: .uint256),
            SolidityWrappedValue(value: swap.secretSeeker.chain, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.symbol, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.contractAddress, type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.invoice ?? String(), type: .string),
            SolidityWrappedValue(value: swap.secretSeeker.receipt ?? String(), type: .string)
        )
        
        let partyType = SolidityType.tuple([
            .address, .uint256, .string, .string, .string, .string, .string
        ])
        
        let swapTuple = SolidityTuple(
            SolidityWrappedValue(value: Data(hex: swap.id), type: .bytes(length: 32)),
            SolidityWrappedValue(value: swap.state.rawValue, type: .uint8),
            SolidityWrappedValue(value: Data(hex: swap.secretHash), type: .bytes(length: 32)),
            SolidityWrappedValue(value: secretHolder, type: partyType),
            SolidityWrappedValue(value: secretSeeker, type: partyType)
        )
        
        let swapType = SolidityType.tuple([
            .bytes(length: 32),
            .uint8,
            .bytes(length: 32),
            partyType,
            partyType
        ])
        
        let inputs = [
            SolidityFunctionParameter(name: "swap", type: swapType),
            SolidityFunctionParameter(name: "secret", type: .bytes(length: nil))
        ]
        
        let method = SolidityNonPayableFunction(name: "settleInvoice", inputs: inputs, handler: self)
        return method.invoke(swapTuple, secret)
    }

    func getSwapTimeout(swap swapId: String) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "swapId", type: .bytes(length: 32))
        ]
        let outputs = [
            SolidityFunctionParameter(name: "", type: .uint256)
        ]

        let method = SolidityConstantFunction(name: "getSwapTimeout", inputs: inputs, outputs: outputs, handler: self)
        return method.invoke(Data(hex: swapId))
    }

    func watchContractEvents(interval: TimeInterval, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void) {
        guard let contractAddress = address else {
            let error = NSError(domain: "InvoiceManagerContract", code: -1, userInfo: [NSLocalizedDescriptionKey: "Contract address is nil"])
            onError(error)
            return
        }
        
        let topics: [EthereumData] = [
            try! EthereumData(ethereumValue: InvoiceManagerContract.Deposit.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: InvoiceManagerContract.Withdraw.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: InvoiceManagerContract.SwapInvoiceCreated.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: InvoiceManagerContract.SwapHolderPaid.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: InvoiceManagerContract.SwapHolderSettled.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: InvoiceManagerContract.SwapSeekerPaid.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: InvoiceManagerContract.SwapSeekerSettled.signature.sha3(.keccak256))
        ]
        
        logPoller = RPCLogPoller(id: "Ethereum: Invoice Manager", eth: eth, addresses: [contractAddress], topics: [topics]) { logs in
            onLogs(logs)
        } onError: { error in
            onError(error)
        }
        
        logPoller?.startPolling(interval: interval)
    }
    
    func stopWatchingContractEvents() {
        logPoller?.stopPolling()
        logPoller = nil
    }
}

