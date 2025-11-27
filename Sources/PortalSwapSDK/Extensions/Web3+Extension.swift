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

    func estimateGas(call: EthereumCall) -> Promise<EthereumQuantity> {
        Promise { resolve, reject in
            estimateGas(call: call) { response in
                switch response.status {
                case .success(let gas):
                    resolve(gas)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }

    func fetchMaxPriorityFeePerGas() -> Promise<EthereumQuantity> {
        Promise { resolve, reject in
            let req = BasicRPCRequest(
                id: properties.rpcId,
                jsonrpc: Web3.jsonrpc,
                method: "eth_maxPriorityFeePerGas",
                params: []
            )

            properties.provider.send(request: req) { (response: Web3Response<EthereumQuantity>) in
                switch response.status {
                case .success(let quantity):
                    resolve(quantity)
                case .failure(let error):
                    reject(error)
                }
            }
        }
    }

    func estimateFeesPerGas() -> Promise<(maxFeePerGas: BigUInt, maxPriorityFeePerGas: BigUInt)> {
        Promise { resolve, reject in
            fetchGasPrice().then { gasPriceQuantity in
                let baseFee = gasPriceQuantity.quantity

                self.fetchMaxPriorityFeePerGas().then { priorityFeeQuantity in
                    let maxPriorityFeePerGas = priorityFeeQuantity.quantity
                    let maxFeePerGas = (baseFee * 2) + maxPriorityFeePerGas
                    resolve((maxFeePerGas, maxPriorityFeePerGas))
                }.catch { _ in
                    do {
                        let maxPriorityFeePerGas = try BigUInt(2.gwei)
                        let maxFeePerGas = (baseFee * 2) + maxPriorityFeePerGas
                        resolve((maxFeePerGas, maxPriorityFeePerGas))
                    } catch {
                        reject(error)
                    }
                }
            }.catch { error in
                reject(error)
            }
        }
    }

    func estimateGasLimit(call: EthereumCall, bufferPercent: Int = 20) -> Promise<BigUInt> {
        Promise { resolve, reject in
            estimateGas(call: call).then { estimatedGasQuantity in
                let gasWithBuffer = (estimatedGasQuantity.quantity * BigUInt(100 + bufferPercent)) / 100
                resolve(gasWithBuffer)
            }.catch { error in
                reject(error)
            }
        }
    }
}
