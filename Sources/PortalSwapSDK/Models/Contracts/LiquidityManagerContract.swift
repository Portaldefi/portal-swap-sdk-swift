import Foundation
import Web3
import Web3ContractABI

struct AssetMintedEvent {
    let id: Data
    let ts: BigUInt
    let nativeAmount: BigUInt
    let portalAmount: BigUInt
    let portalAddress: String
    let chain: String
    let symbol: String
    let contractAddress: String
    let nativeAddress: String
}

struct AssetBurnedEvent {
    let id: Data
    let ts: BigUInt
    let nativeAmount: BigUInt
    let portalAmount: BigUInt
    let portalAddress: String
    let chain: String
    let symbol: String
    let contractAddress: String
    let nativeAddress: String
}

protocol ILiquidityManagerContract: EthereumContract, IRPCLogsPoller {
    static var AssetMinted: SolidityEvent { get }
    static var AssetBurned: SolidityEvent { get }

    func burnAsset(liquidity: Liquidity) -> SolidityInvocation
}

open class LiquidityManagerContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    private var logPoller: RPCLogPoller?
    
    open var constructor: SolidityConstructor?
    open var events: [SolidityEvent] {
        [
            LiquidityManagerContract.AssetMinted,
            LiquidityManagerContract.AssetBurned
        ]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }
}

extension LiquidityManagerContract: ILiquidityManagerContract {
    static var AssetMinted: SolidityEvent {
        let liquidityType: SolidityType = .tuple([
            .bytes(length: 32),
            .uint256,
            .int256,
            .int256,
            .address,
            .string,
            .string,
            .string,
            .string
        ])
        
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "liquidity", type: liquidityType, indexed: false)
        ]
        
        return SolidityEvent(name: "AssetMinted", anonymous: false, inputs: inputs)
    }
    
    static var AssetBurned: SolidityEvent {
        let liquidityType: SolidityType = .tuple([
            .bytes(length: 32),
            .uint256,
            .int256,
            .int256,
            .address,
            .string,
            .string,
            .string,
            .string
        ])
        
        let inputs: [SolidityEvent.Parameter] = [
            SolidityEvent.Parameter(name: "liquidity", type: liquidityType, indexed: false)
        ]
        
        return SolidityEvent(name: "AssetBurned", anonymous: false, inputs: inputs)
    }

    func burnAsset(liquidity: Liquidity) -> SolidityInvocation {
        let inputTypes: [SolidityType] = [
            .bytes(length: 32),
            .uint256,
            .int256,
            .int256,
            .address,
            .string,
            .string,
            .string,
            .string
        ]
        
        let inputs = [
            SolidityFunctionParameter(name: "liquidity", type: .tuple(inputTypes))
        ]
        
        let method = SolidityNonPayableFunction(name: "burnAsset", inputs: inputs, handler: self)
        return method.invoke(liquidity.toSolidityTuple())
    }
    
    func watchContractEvents(interval: TimeInterval, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void) {
        guard let contractAddress = address else {
            let error = NSError(domain: "LiquidityManagerContract", code: -1, userInfo: [NSLocalizedDescriptionKey: "Contract address is nil"])
            onError(error)
            return
        }
        
        let topics: [EthereumData] = [
            try! EthereumData(ethereumValue: LiquidityManagerContract.AssetMinted.signature.sha3(.keccak256)),
            try! EthereumData(ethereumValue: LiquidityManagerContract.AssetBurned.signature.sha3(.keccak256))
        ]
        
        logPoller = RPCLogPoller(id: "Portal: Liquidity Manager", eth: eth, addresses: [contractAddress], topics: [topics]) { logs in
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
