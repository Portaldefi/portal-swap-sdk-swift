import Foundation
import Combine
import Promises

final class Blockchains: BaseClass {
    private let sdk: Sdk
    
    let ethereum: Ethereum
    let lightning: Lightning
    let portal: Portal
    
    let assetManagement: AssetManagement
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains) {
        self.sdk = sdk
        
        ethereum = Ethereum(sdk: sdk, props: props.ethereum)
        lightning = Lightning(sdk: sdk, props: props.lightning)
        portal = Portal(sdk: sdk, props: props.portal)
        
        assetManagement = AssetManagement(props: props.portal)
        
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
        // Subscribe for asset management events
        subscribe(assetManagement.on("log", forwardLog()))
        subscribe(assetManagement.on("info", forwardLog()))
        subscribe(assetManagement.on("warn", forwardLog()))
        subscribe(assetManagement.on("debug", forwardLog()))
        subscribe(assetManagement.on("error", forwardError()))
        
        updateContractAddresses()
    }
    
    func connect() -> Promise<Void> {
        all(ethereum.connect(), lightning.connect(), portal.connect()).then { _ in return }
    }
    
    func disconnect() -> Promise<Void> {
        all(ethereum.disconnect(), lightning.disconnect(), portal.disconnect()).then { _ in return }
    }
    
    func listPools() -> Promise<[Pool]> {
        assetManagement.listPools()
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

extension Blockchains {
    private func updateContractAddresses() {
        do {
            let assetManagementJson = try awaitPromise(
                retry(attempts: 3, delay: 2) {
                    self.fetchContractJSON(from: "https://raw.githubusercontent.com/Portaldefi/deployments/refs/heads/main/portal/AssetManagement.json")
                }
            )
            
            if let contractAddressHex = assetManagementJson["address"] as? String {
                self.assetManagement.assetManagementContractAddress = contractAddressHex
            }
            
            let liquidityPoolJson = try awaitPromise(
                retry(attempts: 3, delay: 2) {
                    self.fetchContractJSON(from: "https://raw.githubusercontent.com/Portaldefi/deployments/refs/heads/main/portal/LiquidityPool.json")
                }
            )
            
            if let contractAddressHex = liquidityPoolJson["address"] as? String {
                self.assetManagement.liquidityPoolContractAddress = contractAddressHex
            }
            
            let dexJson = try awaitPromise(
                retry(attempts: 3, delay: 2) {
                    self.fetchContractJSON(from: "https://raw.githubusercontent.com/Portaldefi/deployments/refs/heads/main/sepolia/DexContract.json")
                }
            )
            
            if let contractAddressHex = dexJson["address"] as? String {
                self.ethereum.dexContractAddress = contractAddressHex
            }
            
            let lpJson = try awaitPromise(
                retry(attempts: 3, delay: 2) {
                    self.fetchContractJSON(from: "https://raw.githubusercontent.com/Portaldefi/deployments/refs/heads/main/sepolia/LiquidityProvider.json")
                }
            )
            
            if let contractAddressHex = lpJson["address"] as? String {
                self.ethereum.liquidityProviderContractAddress = contractAddressHex
            }
            
            let admmJson = try awaitPromise(
                retry(attempts: 3, delay: 2) {
                    self.fetchContractJSON(from: "https://raw.githubusercontent.com/Portaldefi/deployments/refs/heads/main/portal/ADMM.json")
                }
            )
            
            if let contractAddressHex = admmJson["address"] as? String {
                self.portal.admmContractAddress = contractAddressHex
            }
        } catch let contractAddressesError {
            error("fetching contract addresses error", [contractAddressesError])
        }
    }
    
    private func fetchContractJSON(from url: String) -> Promise<[String: Any]> {
        Promise { resolve, reject in
            guard let url = URL(string: url) else {
                throw SwapSDKError.msg("invalid url")
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    return reject(error)
                }

                guard let data = data else {
                    return reject(SwapSDKError.msg("invalid response"))
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        resolve(json)
                    } else {
                        reject(SwapSDKError.msg("invalid json"))
                    }
                } catch {
                    reject(error)
                }
            }.resume()
        }
    }
}
