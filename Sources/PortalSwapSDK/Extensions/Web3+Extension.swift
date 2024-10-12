import Web3
import Promises

extension Web3.Eth {
    func getNonce(address: EthereumAddress) -> Promise<EthereumQuantity> {
        Promise { resolve, reject in
            getTransactionCount(address: address, block: .latest) { nonceResponse in
                switch nonceResponse.status {
                case .success(let nonce):
                    resolve(nonce)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }
    
    func publish(transaction: EthereumSignedTransaction) -> Promise<String> {
        Promise { resolve, reject in
            try sendRawTransaction(transaction: transaction) { response in
                switch response.status {
                case .success(let data):
                    resolve(data.hex())
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }
}
