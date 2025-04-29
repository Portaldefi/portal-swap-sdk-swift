import Foundation
import Promises
import Web3
import Web3ContractABI

final class AssetManagement: BaseClass {
    private let props: SwapSdkConfig.Blockchains.Portal
    private var web3: Web3!
    
    private var assetManagement: IAssetManagerContract?
    private var liquidityPool: ILiquidityPoolContract?
    
    var assets: [Pool.Asset] = []
    var assetManagementContractAddress: String?
    var liquidityPoolContractAddress: String?
    
    init(props: SwapSdkConfig.Blockchains.Portal) {
        self.props = props
        
        web3 = Web3(rpcURL: props.url)
        
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
                assetManagement = web3.eth.Contract(type: AssetManagerContract.self, address: amContractAddress)
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
            
            assetManagement.retrieveAssets().call { response, error in
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
        Promise { [weak self] in
            guard let self else { throw SwapSDKError.msg("AssetManagement is nil") }
            self.assets = try awaitPromise(listAssets())
            return assets.first(where: { $0.blockchainName == blockchainName })
        }
    }
}
