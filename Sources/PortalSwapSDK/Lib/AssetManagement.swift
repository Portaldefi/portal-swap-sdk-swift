import Foundation
import Promises
import Web3
import Web3ContractABI

final class AssetManagement: BaseClass {
    private let props: SwapSdkConfig.Blockchains.Portal
    private var web3: Web3!
    private var websocketProvider: Web3WebSocketProvider!
    
    private var assetManagement: IAssetManagementContract?
    private var liquidityPool: ILiquidityPoolContract?
    
    var assets: [Pool.Asset] = []
    var assetManagementContractAddress: String?
    var liquidityPoolContractAddress: String?
    
    init(props: SwapSdkConfig.Blockchains.Portal) {
        self.props = props
        
        web3 = Web3(rpcURL: "http://node.playnet.portaldefi.zone:9545")
        
        super.init(id: "asset.manager")
    }
    
    func listPools() -> Promise<[Pool]> {
        Promise { [unowned self] resolve, reject in
            if
                let amContractAddressHex = assetManagementContractAddress,
                let amContractAddress = try? EthereumAddress(
                    hex: amContractAddressHex,
                    eip55: Utils.isEIP55Compliant(address: amContractAddressHex)
                ),
                let poolContractAddressHex = liquidityPoolContractAddress,
                let poolContractAddress = try? EthereumAddress(
                    hex: poolContractAddressHex,
                    eip55: Utils.isEIP55Compliant(address: poolContractAddressHex)
                )
            {
                assetManagement = web3.eth.Contract(type: AssetManagementContract.self, address: amContractAddress)
                liquidityPool = web3.eth.Contract(type: LiquidityPoolContract.self, address: poolContractAddress)
            }
            
            listAssets().then { [weak self] assets in
                guard let self else {
                    return reject(SwapSDKError.msg("AssetManagement is nil"))
                }
                                                
                listPools().then { poolModels in
                    resolve(
                        poolModels.compactMap { model in
                            let baseAsset = assets.first(where: { $0.id.hex(eip55: true) == model.baseAsset.hex(eip55: true) })
                            let quoteAsset = assets.first(where: { $0.id.hex(eip55: true) == model.quoteAsset.hex(eip55: true) })
                           
                            guard let baseAsset, let quoteAsset else { return nil }
                            
                            return Pool(
                                model: model,
                                baseAsset: baseAsset,
                                quoteAsset: quoteAsset
                            )
                        }
                    )
                }.catch { fetchPoolsError in
                    reject(fetchPoolsError)
                }
            }.catch { fetchAssetsError in
                reject(fetchAssetsError)
            }
        }
    }
    
    private func listAssets() -> Promise<[Pool.Asset]> {
        Promise { [unowned self] resolve, reject in
            guard let assetManagement else {
                return reject(SwapSDKError.msg("AssetManagement contract is not set"))
            }
            
            assetManagement.listAssets().call { response, error in
                if let response {
                    guard let assetsArray = response[""] as? [Any] else {
                        return reject(SwapSDKError.msg("Failed to parse assets array"))
                    }

                    self.assets = assetsArray.compactMap { dataArray in
                        guard let asset = dataArray as? [Any],
                              let id = asset[0] as? EthereumAddress,
                              let name = asset[1] as? String,
                              let symbol = asset[2] as? String,
                              let logo = asset[3] as? String,
                              let blockchainId = asset[4] as? BigUInt,
                              let blockchainName = asset[5] as? String,
                              let blockchainAddress = asset[6] as? String,
                              let blockchainDecimals = asset[7] as? UInt8
                        else {
                            return nil
                        }
                        
                        return Pool.Asset(
                            id: id,
                            name: name,
                            symbol: symbol,
                            logo: logo,
                            blockchainId: blockchainId,
                            blockchainName: blockchainName,
                            blockchainAddress: blockchainAddress,
                            blockchainDecimals: blockchainDecimals
                        )
                    }
                    
                    resolve(self.assets)
                } else if let error {
                    reject(error)
                } else {
                    resolve([])
                }
            }
        }
    }
    
    private func listPools() -> Promise<[PoolModel]> {
        Promise { [unowned self] resolve, reject in
            guard let liquidityPool else {
                return reject(SwapSDKError.msg("Liquidity Pool contract is not set"))
            }
            
            liquidityPool.listPools().call { response, error in
                if let response {
                    guard let poolsArray = response[""] as? [Any] else {
                        return reject(SwapSDKError.msg("Failed to parse pools array"))
                    }
                    
                    resolve(
                        poolsArray.compactMap { dataArray in
                            guard let pool = dataArray as? [Any],
                                  let id = pool[0] as? Data,
                                  let baseAsset = pool[1] as? EthereumAddress,
                                  let quoteAsset = pool[2] as? EthereumAddress,
                                  let fee = pool[3] as? BigUInt,
                                  let minOrderSize = pool[4] as? BigUInt,
                                  let maxOrderSize = pool[5] as? BigUInt
                            else {
                                return nil
                            }
                            
                            return PoolModel(
                                id: id,
                                baseAsset: baseAsset,
                                quoteAsset: quoteAsset,
                                fee: fee,
                                minOrderSize: minOrderSize,
                                maxOrderSize: maxOrderSize
                            )
                        }
                    )
                } else if let error {
                    reject(error)
                } else {
                    resolve([])
                }
            }
        }
    }
    
    func retrieveAsset(_ id: String) -> Pool.Asset? {
        assets.first(where: { $0.id.hex(eip55: false) == id })
    }
    
    func retrieveAssetByNativeProps(blockchainName: String, blockchainAddress: String) -> Promise<Pool.Asset?> {
        Promise { [unowned self] resolve, reject in
            listAssets().then { assets in
                self.assets = assets
                
                resolve(
                    assets.first(where: { $0.blockchainName == blockchainName })
                )
            }.catch { listAssetsError in
                reject(listAssetsError)
            }
//            guard let assetManagement else {
//                return reject(SwapSDKError.msg("Asset Management contract is not set"))
//            }
//            
//            assetManagement
//                .retrieveAssetByNativeProps(
//                    blockchainName: blockchainName,
//                    blockchainAddress: blockchainAddress
//                )
//                .call { response, error in
//                    if let response {
//                        guard let asset = response[""] else {
//                            return reject(SwapSDKError.msg("Failed to parse assets array"))
//                        }
//                        
//                        resolve(
//                            Pool.Asset(id: EthereumAddress(hexString: "")!, name: "", symbol: "", logo: "", blockchainId: 0, blockchainName: "", blockchainAddress: "", blockchainDecimals: 0)
//                        )
//                    } else if let error {
//                        reject(error)
//                    } else {
//                        resolve(nil)
//                    }
//                }
//            
//            guard let amAbi = props.contracts["AssetManagement"] as? [String: Any],
//                  let abiArray = amAbi["abi"] as? [[String: Any]],
//                  let amContractAddressHex = amAbi["address"] as? String,
//                  let amContractAddress = try? EthereumAddress(
//                    hex: amContractAddressHex,
//                    eip55: Utils.isEIP55Compliant(address: amContractAddressHex)
//                  ) 
//            else {
//                return reject(SwapSDKError.msg("Asset Management contract is not set"))
//            }
//            
//            let dexContractData = try JSONSerialization.data(withJSONObject: abiArray, options: [])
//            
//            let contract = try web3.eth.Contract(json: dexContractData, abiKey: nil, address: amContractAddress)
//            
//            let params = SolidityTuple([
//                SolidityWrappedValue(value: blockchainName, type: .string),
//                SolidityWrappedValue(value: blockchainAddress, type: .string)
//            ])
//
//            
//            contract["retrieveAssetByNativeProps"]?(params).call(completion: { response, error in
//                if let response {
//                    guard let assetsArray = response[""] as? [Any] else {
//                        return reject(SwapSDKError.msg("Failed to parse assets array"))
//                    }
//                    
//                    resolve(
//                        Pool.Asset(id: EthereumAddress(hexString: "")!, name: "", symbol: "", logo: "", blockchainId: 0, blockchainName: "", blockchainAddress: "", blockchainDecimals: 0)
//                    )
//                } else if let error {
//                    reject(error)
//                } else {
//                    resolve(nil)
//                }
//            })
        }
    }
}
