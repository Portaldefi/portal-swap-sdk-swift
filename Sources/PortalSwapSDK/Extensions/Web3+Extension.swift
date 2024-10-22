import Web3
import Promises

extension Web3.Eth {
    func blockNumber() -> Promise<EthereumQuantity> {
        Promise { resolve, reject in
            blockNumber { response in
                switch response.status {
                case .success(let blockNumber):
                    resolve(blockNumber)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }
    
    func getLogs(addresses: [EthereumAddress]?, topics: [[EthereumData]]?, fromBlock: EthereumQuantityTag, toBlock: EthereumQuantityTag) -> Promise<[EthereumLogObject]> {
        Promise { resolve, reject in
            getLogs(addresses: addresses, topics: topics, fromBlock: fromBlock, toBlock: toBlock) { response in
                switch response.status {
                case .success(let logs):
                    guard !logs.isEmpty else {
                        return reject(SwapSDKError.msg("Empty logs"))
                    }
                    resolve(logs)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }
    
    func fetchReceipt(txHash: EthereumData) -> Promise<EthereumTransactionReceiptObject> {
        Promise { resolve, reject in
            getTransactionReceipt(transactionHash: txHash) { response in
                switch response.status {
                case .success(let receipt):
                    guard let receipt else {
                        return reject(SwapSDKError.msg("Fething receipt failed"))
                    }
                    resolve(receipt)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }
    
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
    
    func fetchGasPrice() -> Promise<EthereumQuantity> {
        Promise { resolve, reject in
            gasPrice { response in
                switch response.status {
                case .success(let gasPrice):
                    resolve(gasPrice)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }
}
