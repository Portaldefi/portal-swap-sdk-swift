import Foundation
import Combine
import Promises
import BigInt

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
        ethereum.on("log", forwardLog())
        ethereum.on("error", forwardError())
        ethereum.on("order.created", forwardEvent("order.created"))
        ethereum.on("invoice.settled", forwardEvent("invoice.settled"))
        // Subscribe for portal events
        portal.on("log", forwardLog())
        portal.on("error", forwardError())
        portal.on("lp.invoice.created", forwardEvent("lp.invoice.created"))
        portal.on("swap.created", forwardEvent("swap.created"))
        portal.on("swap.validated", forwardEvent("swap.validated"))
        portal.on("swap.matched", forwardEvent("swap.matched"))
        // Subscribe for lightning events
        lightning.on("log", forwardLog())
        lightning.on("error", forwardError())
        lightning.on("invoice.paid", forwardEvent("invoice.paid"))
        lightning.on("invoice.settled", forwardEvent("invoice.settled"))
        lightning.on("invoice.canceled", forwardEvent("invoice.canceled"))
        // Subscribe for asset management events
        assetManagement.on("log", forwardLog())
        assetManagement.on("info", forwardLog())
        assetManagement.on("warn", forwardLog())
        assetManagement.on("debug", forwardLog())
        assetManagement.on("error", forwardError())
        
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
    
    func priceBtcToEth() -> Promise<BigUInt> {
        portal.priceBtcToEth()
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
