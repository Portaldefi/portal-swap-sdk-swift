import Combine
import Promises

class Blockchains: BaseClass {
    private let sdk: Sdk!
    public let ethereum: IBlockchain!
    public let lightning: IBlockchain!
    
    private var subscriptions = Set<AnyCancellable>()
    
    private lazy var onError: ([Any]) -> Void = { [weak self] args in
        self?.emit(event: "error", args: args)
    }
    
    private lazy var forwardLogEvent: ([Any]) -> Void = { [weak self] args in
        self?.emit(event: "log", args: args)
    }
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains) {
        self.sdk = sdk
        
        self.ethereum = Ethereum(sdk: sdk, props: props.ethereum)
        self.lightning = Lightning(sdk: sdk, props: props.lightning)
        
        super.init(id: "Blockchains")
        
        self.ethereum.on("log", forwardLogEvent).store(in: &subscriptions)
        self.lightning.on("log", forwardLogEvent).store(in: &subscriptions)
        self.ethereum.on("error", onError).store(in: &subscriptions)
        self.lightning.on("error", onError).store(in: &subscriptions)
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            all(ethereum.connect(), lightning.connect())
                .then { ethereum, lightning in
                    resolve(())
                }.catch { error in
                    reject(error)
                }
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            all(ethereum.disconnect(), lightning.disconnect())
                .then { ethereum, lightning in
                    resolve(())
                }.catch { error in
                    reject(error)
                }
        }
    }
    
    func blockchain(id: String) -> IBlockchain? {
        switch id {
        case "ethereum":
            return ethereum
        case "lightning":
            return lightning
        default:
            return nil
        }
    }
}
