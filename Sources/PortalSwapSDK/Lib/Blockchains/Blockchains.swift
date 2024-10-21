import Combine
import Promises

final class Blockchains: BaseClass {
    private let sdk: Sdk
    
    let ethereum: Ethereum
    let lightning: Lightning
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
        subscribe(ethereum.on("order.created", forwardEvent("order.created")))
        subscribe(ethereum.on("invoice.settled", forwardEvent("invoice.settled")))
        // Subscribe for portal events
        subscribe(portal.on("log", forwardLog()))
        subscribe(portal.on("error", forwardError()))
        subscribe(portal.on("lp.invoice.created", forwardEvent("lp.invoice.created")))
        subscribe(portal.on("swap.created", forwardEvent("swap.created")))
        subscribe(portal.on("swap.validated", forwardEvent("swap.validated")))
        subscribe(portal.on("swap.matched", forwardEvent("swap.matched")))
        // Subscribe for lightning events
        subscribe(lightning.on("log", forwardLog()))
        subscribe(lightning.on("error", forwardError()))
        subscribe(lightning.on("invoice.paid", forwardEvent("invoice.paid")))
        subscribe(lightning.on("invoice.settled", forwardEvent("invoice.settled")))
        subscribe(lightning.on("invoice.canceled", forwardEvent("invoice.canceled")))
    }
    
    func connect() -> Promise<Void> {
        all(ethereum.connect(), lightning.connect(), portal.connect()).then { _ in return }
    }
    
    func disconnect() -> Promise<Void> {
        all(ethereum.disconnect(), lightning.disconnect(), portal.disconnect()).then { _ in return }
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
