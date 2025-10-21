import Foundation
import Web3
import Web3ContractABI

protocol ISwapManagerContract: EthereumContract, IRPCLogsPoller {
    func createSwap(
        partyNativeAddress: String,
        partyPortalAddress: EthereumAddress,
        partyAsset: Data,
        partyAmount: BigUInt,
        counterpartyNativeAddress: String,
        counterpartyPortalAddress: EthereumAddress,
        counterpartyAsset: Data,
        counterpartyAmount: BigUInt
    ) -> SolidityInvocation

    func registerInvoice(_ swap: Swap) -> SolidityInvocation
    func validator() -> SolidityInvocation
}

open class SwapManagerContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    private var logPoller: RPCLogPoller?

    open var constructor: SolidityConstructor? = nil

    open var events: [SolidityEvent] {
        [SwapManagerContract.SwapMatched, SwapManagerContract.SwapHolderInvoiced, SwapManagerContract.SwapSeekerInvoiced]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }

    public static let SwapMatched = SolidityEvent(name: "SwapMatched", anonymous: false, inputs: [
        SolidityEvent.Parameter(name: "swap", type: .tuple([
            .bytes(length: 32),   // id
            .uint8,               // state (enum SwapState as uint8)
            .bytes(length: 32),   // secretHash
            .tuple([              // secretHolder
                .address,         // portalAddress
                .uint256,         // amount
                .string,          // chain
                .string,          // symbol
                .string,          // contractAddress
                .string,          // invoice
                .string           // receipt
            ]),
            .tuple([              // secretSeeker
                .address,         // portalAddress
                .uint256,         // amount
                .string,          // chain
                .string,          // symbol
                .string,          // contractAddress
                .string,          // invoice
                .string           // receipt
            ])
        ]), indexed: false)
    ])

    public static let SwapHolderInvoiced = SolidityEvent(name: "SwapHolderInvoiced", anonymous: false, inputs: [
        SolidityEvent.Parameter(name: "swap", type: .tuple([
            .bytes(length: 32),   // id
            .uint8,               // state (enum SwapState as uint8)
            .bytes(length: 32),   // secretHash
            .tuple([              // secretHolder
                .address,         // portalAddress
                .uint256,         // amount
                .string,          // chain
                .string,          // symbol
                .string,          // contractAddress
                .string,          // invoice
                .string           // receipt
            ]),
            .tuple([              // secretSeeker
                .address,         // portalAddress
                .uint256,         // amount
                .string,          // chain
                .string,          // symbol
                .string,          // contractAddress
                .string,          // invoice
                .string           // receipt
            ])
        ]), indexed: false)
    ])

    public static let SwapSeekerInvoiced = SolidityEvent(name: "SwapSeekerInvoiced", anonymous: false, inputs: [
        SolidityEvent.Parameter(name: "swap", type: .tuple([
            .bytes(length: 32),   // id
            .uint8,               // state (enum SwapState as uint8)
            .bytes(length: 32),   // secretHash
            .tuple([              // secretHolder
                .address,         // portalAddress
                .uint256,         // amount
                .string,          // chain
                .string,          // symbol
                .string,          // contractAddress
                .string,          // invoice
                .string           // receipt
            ]),
            .tuple([              // secretSeeker
                .address,         // portalAddress
                .uint256,         // amount
                .string,          // chain
                .string,          // symbol
                .string,          // contractAddress
                .string,          // invoice
                .string           // receipt
            ])
        ]), indexed: false)
    ])
}

extension SwapManagerContract: ISwapManagerContract {
    func createSwap(
        partyNativeAddress: String,
        partyPortalAddress: EthereumAddress,
        partyAsset: Data,
        partyAmount: BigUInt,
        counterpartyNativeAddress: String,
        counterpartyPortalAddress: EthereumAddress,
        counterpartyAsset: Data,
        counterpartyAmount: BigUInt
    ) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "_partyNativeAddress", type: .string),
            SolidityFunctionParameter(name: "_partyPortalAddress", type: .address),
            SolidityFunctionParameter(name: "_partyAsset", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "_partyAmount", type: .uint256),
            SolidityFunctionParameter(name: "_counterpartyNativeAddress", type: .string),
            SolidityFunctionParameter(name: "_counterpartyPortalAddress", type: .address),
            SolidityFunctionParameter(name: "_counterpartyAsset", type: .bytes(length: 32)),
            SolidityFunctionParameter(name: "_counterpartyAmount", type: .uint256)
        ]
        let method = SolidityNonPayableFunction(name: "createSwap", inputs: inputs, handler: self)
        return method.invoke(
            partyNativeAddress,
            partyPortalAddress,
            partyAsset,
            partyAmount,
            counterpartyNativeAddress,
            counterpartyPortalAddress,
            counterpartyAsset,
            counterpartyAmount
        )
    }

    func registerInvoice(_ swap: Swap) -> SolidityInvocation {
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
            SolidityWrappedValue(value: UInt8(swap.state.rawValue), type: .uint8),
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
        
        let method = SolidityNonPayableFunction(name: "registerInvoice", inputs: inputs, handler: self)
        return method.invoke(swapTuple)
    }

    func validator() -> SolidityInvocation {
        let outputs = [SolidityFunctionParameter(name: "", type: .address)]
        let method = SolidityConstantFunction(name: "validator", outputs: outputs, handler: self)
        return method.invoke()
    }

    func watchContractEvents(interval: TimeInterval, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void) {
        guard let contractAddress = address else {
            let error = NSError(domain: "SwapManagerContract", code: -1, userInfo: [NSLocalizedDescriptionKey: "Contract address is nil"])
            onError(error)
            return
        }
        
        let topics: [EthereumData] = [
            try! EthereumData(ethereumValue: SwapManagerContract.SwapMatched.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: SwapManagerContract.SwapHolderInvoiced.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: SwapManagerContract.SwapSeekerInvoiced.signature.sha3(.keccak256))
        ]

        logPoller = RPCLogPoller(id: "Portal: Swap Manager", eth: eth, addresses: [contractAddress], topics: [topics]) { logs in
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
