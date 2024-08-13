import Foundation
import Promises
import Web3
import Web3ContractABI

final class AssetManagement: BaseClass {
    struct AssetPairModel {
        let sellAsset: EthereumAddress
        let buyAsset: EthereumAddress
        let poolFee: BigUInt
    }
    
    private let props: SwapSdkConfig.Blockchains.Portal
    private var web3: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    
    init(props: SwapSdkConfig.Blockchains.Portal) {
        self.props = props
        
        super.init(id: "asset.manager")
    }
    
    func assetPairs() -> Promise<[AssetPair]> {
        Promise { [unowned self] resolve, reject in
            if websocketProvider == nil {
                websocketProvider = try Web3WebSocketProvider(wsUrl: props.url)
            }
            
            if web3 == nil {
                web3 = Web3(provider: websocketProvider)
            }
            
            guard
                let contract = props.contracts["AssetManagement"] as? [String: Any],
                let abiArray = contract["abi"] as? [[String: Any]],
                let contractAddressHex = contract["address"] as? String
            else {
                return reject(SwapSDKError.msg("Portal cannot prepare AssetManagement contract"))
            }
            
            let assetManagementContractAddresIsEipp55 = Utils.isEIP55Compliant(address: contractAddressHex)
            
            let assetManagementContractAddress = try EthereumAddress(hex: contractAddressHex, eip55: assetManagementContractAddresIsEipp55)
            let assetManagementContractData = try JSONSerialization.data(withJSONObject: abiArray, options: [])
            
            let assetManagementContract = try web3.eth.Contract(json: assetManagementContractData, abiKey: nil, address: assetManagementContractAddress)
            
            let startIndex = BigUInt(UInt64(0).makeBytes())
            let pageSize = BigUInt(UInt64(0).makeBytes())

            let params = SolidityTuple([
                SolidityWrappedValue(value: startIndex, type: .uint256),
                SolidityWrappedValue(value: pageSize, type: .uint256)
            ])
            
            assetManagementContract["retrieveAssets"]?(params).call(completion: { response, error in
                if let response {
                    let assets = self.parseAssets(response: response)
                    
                    assetManagementContract["retrieveAssetPairs"]?(params).call(completion: { response, error in
                        if let response {
                            let parsedPairs = self.parseAssetPairs(response: response)
                            
                            var assetPairs = [AssetPair]()

                            for pair in parsedPairs {
                                let base = assets.first(where: { $0.portalAddress == pair.sellAsset })
                                let quote = assets.first(where: { $0.portalAddress == pair.buyAsset })
                               
                                guard let base, let quote else { continue }
                                
                                assetPairs.append(AssetPair(base: base, quote: quote))
                            }
                            
                            self.websocketProvider.webSocket.close().whenComplete { _ in
//                                guard self.websocketProvider.closed else {
//                                    return reject(SwapSDKError.msg("Web socket isnt's closed"))
//                                }
                                resolve(assetPairs)
                            }
                        }
                        if let error { reject(error) }
                    })
                }
                
                if let error { reject(error) }
            })
        }
    }
    
    func parseAssets(response: [String: Any]) -> [AssetPair.Asset] {
        guard let assetsArray = response[""] as? [[String: Any]] else {
            print("Failed to parse assets array")
            return []
        }
        
        return assetsArray.compactMap { asset in
            guard let nativeAddress = asset["nativeAddress"] as? EthereumAddress,
                  let portalAddress = asset["portalAddress"] as? EthereumAddress,
                  let decimals = asset["decimals"] as? UInt8,
                  let minOrderSize = asset["minOrderSize"] as? BigUInt,
                  let maxOrderSize = asset["maxOrderSize"] as? BigUInt,
                  let unit = asset["unit"] as? String,
                  let multiplier = asset["multiplier"] as? UInt64,
                  let chainId = asset["chainId"] as? UInt32,
                  let deleted = asset["deleted"] as? Bool,
                  let name = asset["name"] as? String,
                  let logo = asset["logo"] as? String,
                  let chainName = asset["chainName"] as? String,
                  let symbol = asset["symbol"] as? String  else {
                return nil
            }
            
            return AssetPair.Asset(
                nativeAddress: nativeAddress,
                portalAddress: portalAddress,
                decimals: decimals,
                minOrderSize: minOrderSize,
                maxOrderSize: maxOrderSize,
                unit: unit,
                multiplier: multiplier,
                chainId: chainId,
                deleted: deleted,
                name: name,
                logo: logo,
                chainName: chainName,
                symbol: symbol
            )
        }
    }
    
    func parseAssetPairs(response: [String: Any]) -> [AssetPairModel] {
        guard let assetPairsArray = response[""] as? [[String: Any]] else {
            print("Failed to parse asset pairs array")
            return []
        }
        
        return assetPairsArray.compactMap { pair in
            guard let sellAsset = pair["sellAsset"] as? EthereumAddress,
                  let buyAsset = pair["buyAsset"] as? EthereumAddress,
                  let poolFee = pair["poolFee"] as? BigUInt else { return nil }
            
            return AssetPairModel(
                sellAsset: sellAsset,
                buyAsset: buyAsset,
                poolFee: poolFee
            )
        }
    }
}
