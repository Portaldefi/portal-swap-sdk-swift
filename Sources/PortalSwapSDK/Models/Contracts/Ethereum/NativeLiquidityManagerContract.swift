import Foundation
import BigInt
import Web3
import Web3ContractABI

protocol INativeLiquidityManagerContract: EthereumContract, IRPCLogsPoller {
    static var Deposit: SolidityEvent { get }
    static var Withdraw: SolidityEvent { get }
    static var SwapInvoiceCreated: SolidityEvent { get }
    static var SwapHolderPaid: SolidityEvent { get }
    static var SwapHolderSettled: SolidityEvent { get }
    static var SwapSeekerPaid: SolidityEvent { get }
    static var SwapSeekerSettled: SolidityEvent { get }

    func ethDeposit(assetAddress: EthereumAddress, nativeAmount: BigInt, nativeAddress: EthereumAddress) -> SolidityInvocation
}

class NativeLiquidityManagerContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    private var logPoller: RPCLogPoller?
    
    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {
        [
            NativeLiquidityManagerContract.Deposit,
            NativeLiquidityManagerContract.Withdraw,
            NativeLiquidityManagerContract.SwapInvoiceCreated,
            NativeLiquidityManagerContract.SwapHolderPaid,
            NativeLiquidityManagerContract.SwapHolderSettled,
            NativeLiquidityManagerContract.SwapSeekerPaid,
            NativeLiquidityManagerContract.SwapSeekerSettled
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

extension NativeLiquidityManagerContract: INativeLiquidityManagerContract {
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
    
    func ethDeposit(assetAddress: EthereumAddress, nativeAmount: BigInt, nativeAddress: EthereumAddress) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "assetAddress", type: .address),
            SolidityFunctionParameter(name: "nativeAmount", type: .uint256),
            SolidityFunctionParameter(name: "portalAddress", type: .address)
        ]
        let method = SolidityPayableFunction(name: "deposit", inputs: inputs, handler: self)
        return method.invoke(assetAddress, nativeAmount, nativeAddress)
    }
    
    func watchContractEvents(interval: TimeInterval, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void) {
        guard let contractAddress = address else {
            let error = NSError(domain: "NativeLiquidityManagerContract", code: -1, userInfo: [NSLocalizedDescriptionKey: "Contract address is nil"])
            onError(error)
            return
        }
        
        let topics: [EthereumData] = [
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.Deposit.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.Withdraw.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.SwapInvoiceCreated.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.SwapHolderPaid.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.SwapHolderSettled.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.SwapSeekerPaid.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: NativeLiquidityManagerContract.SwapSeekerSettled.signature.sha3(.keccak256))
        ]
        
        logPoller = RPCLogPoller(id: "Ethereum: Native Liquidity Manager", eth: eth, addresses: [contractAddress], topics: [topics]) { logs in
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
