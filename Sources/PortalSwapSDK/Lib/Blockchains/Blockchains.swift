import Combine
import Promises

final class Blockchains: BaseClass {
    private let sdk: Sdk
    private let ethereum: IBlockchain
    private let lightning: IBlockchain
    private let portal: IBlockchain
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains) {
        self.sdk = sdk
        
        ethereum = Ethereum(sdk: sdk, props: props.ethereum)
        lightning = Lightning(sdk: sdk, props: props.lightning)
        portal = Portal(sdk: sdk, props: props.portal)
        
        super.init(id: "Blockchains")
        
        subscribe(ethereum.on("log", forwardLog()))
        subscribe(lightning.on("log", forwardLog()))
        subscribe(portal.on("log", forwardLog()))
        subscribe(ethereum.on("error", forwardError()))
        subscribe(lightning.on("error", forwardError()))
        subscribe(portal.on("error", forwardError()))
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            all(ethereum.connect(), lightning.connect(), portal.connect())
                .then { ethereum, lightning, portal in
                    resolve(())
                }.catch { error in
                    reject(error)
                }
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            all(ethereum.disconnect(), lightning.disconnect(), portal.disconnect())
                .then { ethereum, lightning, portal in
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
        case "portal":
            return portal
        default:
            return nil
        }
    }
}
