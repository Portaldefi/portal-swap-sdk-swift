import Combine
import Promises

class Blockchains: BaseClass {
    private let sdk: Sdk
    
    public let ethereum: IBlockchain
    public let lightning: IBlockchain
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains) {
        self.sdk = sdk
        
        ethereum = Ethereum(sdk: sdk, props: props.ethereum)
        lightning = Lightning(sdk: sdk, props: props.lightning)
        
        super.init(id: "Blockchains")
        
        subscribe(ethereum.on("log", forwardLog()))
        subscribe(lightning.on("log", forwardLog()))
        subscribe(ethereum.on("error", forwardError()))
        subscribe(lightning.on("error", forwardError()))
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
