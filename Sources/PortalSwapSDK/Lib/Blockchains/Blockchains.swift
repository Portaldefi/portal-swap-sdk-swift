import Combine
import Promises

final class Blockchains: BaseClass {
    private let sdk: Sdk
    private let ethereum: IBlockchain
    private let lightning: IBlockchain
    let portal: Portal
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains) {
        self.sdk = sdk
        
        ethereum = Ethereum(sdk: sdk, props: props.ethereum)
        lightning = Lightning(sdk: sdk, props: props.lightning)
        portal = Portal(sdk: sdk, props: props.portal)
        
        super.init(id: "Blockchains")
        
        // Subscribe for eth events
        subscribe(ethereum.on("log", forwardLog()))
        subscribe(ethereum.on("error", forwardError()))
        subscribe(ethereum.on("trader.intent.created", forwardEvent("trader.intent.created")))
        // Subscribe for portal events
        subscribe(portal.on("log", forwardLog()))
        subscribe(portal.on("error", forwardError()))
        subscribe(portal.on("notary.validator.match.intent", forwardEvent("notary.validator.match.intent")))
        // Subscribe for lightning events
        subscribe(lightning.on("log", forwardLog()))
        subscribe(lightning.on("error", forwardError()))
        subscribe(lightning.on("invoice.paid", forwardEvent("invoice.paid")))
        subscribe(lightning.on("invoice.settled", forwardEvent("invoice.settled")))
        subscribe(lightning.on("invoice.canceled", forwardEvent("invoice.canceled")))
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
