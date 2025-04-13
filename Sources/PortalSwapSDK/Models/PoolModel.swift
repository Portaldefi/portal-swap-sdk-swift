import Foundation
import Web3

struct PoolModel {
    let id: Data
    let baseAsset: EthereumAddress
    let quoteAsset: EthereumAddress
    let fee: BigUInt
    let minOrderSize: BigUInt
    let maxOrderSize: BigUInt
}
