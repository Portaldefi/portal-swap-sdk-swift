import Foundation
import Web3
import Web3ContractABI
import BigInt

protocol IOrderbookMarketContract: EthereumContract, IRPCLogsPoller {
    static var OrderCreated: SolidityEvent { get }

    func openOrder(sellAsset: String, sellAmount: BigInt, buyAsset: String, buyAmmount: BigInt, orderType: Order.OrderType) -> SolidityInvocation
}

open class OrderbookMarketContract: StaticContract {
    public let address: EthereumAddress?
    public let eth: Web3.Eth
    private var logPoller: RPCLogPoller?

    open var constructor: SolidityConstructor? = nil

    open var events: [SolidityEvent] {
        [OrderbookMarketContract.OrderCreated]
    }

    public required init(address: EthereumAddress?, eth: Web3.Eth) {
        self.address = address
        self.eth = eth
    }

    public static let OrderCreated = SolidityEvent(name: "OrderCreated", anonymous: false, inputs: [
        SolidityEvent.Parameter(name: "id", type: .uint256, indexed: false),
        SolidityEvent.Parameter(name: "timestamp", type: .uint256, indexed: false),
        SolidityEvent.Parameter(name: "trader", type: .address, indexed: true),
        SolidityEvent.Parameter(name: "sellAsset", type: .uint256, indexed: true),
        SolidityEvent.Parameter(name: "sellAmount", type: .uint256, indexed: false),
        SolidityEvent.Parameter(name: "buyAsset", type: .uint256, indexed: true),
        SolidityEvent.Parameter(name: "buyAmount", type: .uint256, indexed: false),
        SolidityEvent.Parameter(name: "isOpen", type: .bool, indexed: false),
        SolidityEvent.Parameter(name: "orderType", type: .uint8, indexed: false)
    ])
}

extension OrderbookMarketContract: IOrderbookMarketContract {
    func openOrder(sellAsset: String, sellAmount: BigInt, buyAsset: String, buyAmmount: BigInt, orderType: Order.OrderType) -> SolidityInvocation {
        let inputs = [
            SolidityFunctionParameter(name: "sellAsset", type: .uint256),
            SolidityFunctionParameter(name: "sellAmount", type: .uint256),
            SolidityFunctionParameter(name: "buyAsset", type: .uint256),
            SolidityFunctionParameter(name: "buyAmount", type: .uint256),
            SolidityFunctionParameter(name: "orderType", type: .uint8)
        ]
        
        let sellAssetBigInt = hexStringToBigInt(sellAsset)
        let buyAssetBigInt = hexStringToBigInt(buyAsset)
        
        let method = SolidityNonPayableFunction(name: "openOrder", inputs: inputs, handler: self)
        
        return method.invoke(
            sellAssetBigInt,
            sellAmount,
            buyAssetBigInt,
            buyAmmount,
            orderType.rawValue
        )
    }
    
    func hexStringToBigInt(_ hexString: String) -> BigInt {
        // Remove "0x" prefix if present
        let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        
        // Convert hex string to BigInt
        return BigInt(cleanHex, radix: 16) ?? BigInt(0)
    }
    
    func watchContractEvents(interval: TimeInterval, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void) {
        guard let contractAddress = address else {
            let error = NSError(domain: "OrderbookMarketContract", code: -1, userInfo: [NSLocalizedDescriptionKey: "Contract address is nil"])
            onError(error)
            return
        }
        
        let topics: [EthereumData] = [
            try! EthereumData(ethereumValue: OrderbookMarketContract.OrderCreated.signature.sha3(.keccak256)),
        ]
        
        logPoller = RPCLogPoller(id: "Portal: Order Market", eth: eth, addresses: [contractAddress], topics: [topics]) { logs in
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
    

