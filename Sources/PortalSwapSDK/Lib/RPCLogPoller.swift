import Foundation
import BigInt
import Web3
/// A log polling utility that uses RPC polling (eth_getLogs) to subscribe to contract events.
/// It accepts an Ethereum address, an optional topics filter (using [[EthereumData]]),
/// and closures for handling logs and errors.
class RPCLogPoller {
    private let pollerId: String
    private let eth: Web3.Eth
    private let addresses: [EthereumAddress]
    private let topics: [[EthereumData]]?
    private let onLogs: ([EthereumLogObject]) -> Void
    private let onError: (Error) -> Void
    private var timer: Timer?
    private var lastProcessedBlock: BigUInt?
    private var isPolling: Bool = false
    
    private let queue = DispatchQueue(label: "rpc.logpoller.queue")
    
    /// Initializes the LogPooler.
    ///
    /// - Parameters:
    ///   - eth: The Web3.Eth instance used for RPC calls.
    ///   - address: The Ethereum contract address to watch.
    ///   - topics: Optional filter for event topics (each inner array corresponds to a topic position).
    ///   - onLogs: Closure invoked with new logs.
    ///   - onError: Closure invoked if an error occurs during polling.
    init(id: String, eth: Web3.Eth, addresses: [EthereumAddress], topics: [[EthereumData]]? = nil, onLogs: @escaping ([EthereumLogObject]) -> Void, onError: @escaping (Error) -> Void) {
        self.pollerId = id
        self.eth = eth
        self.addresses = addresses
        self.topics = topics
        self.onLogs = onLogs
        self.onError = onError
    }
    
    /// Starts polling for logs using a fixed interval (default is 15 seconds).
    func startPolling(interval: TimeInterval = 1.0) {
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(timeInterval: interval,
                                              target: self,
                                              selector: #selector(self.pollLogs),
                                              userInfo: nil,
                                              repeats: true)
        }
    }
    
    /// Stops the polling process.
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Polls for new logs.
    /// This method first gets the latest block number, determines the range to query,
    /// and then calls `eth.getLogs` to retrieve logs in that range.
    @objc private func pollLogs() {
        queue.async {
            guard !self.isPolling else {
                return
            }
            self.isPolling = true
                        
            self.eth.blockNumber { [weak self] response in
                guard let self = self else { return }
                
                switch response.status {
                case .success(let latest):
                    let latestBlock = latest.quantity
                                        
                    // compute fromBlock under the queue
                    let fromBlock: BigUInt = {
                        if let last = self.lastProcessedBlock {
                            return last + 1
                        } else {
                            return latestBlock
                        }
                    }()
                    
                    guard latestBlock >= fromBlock else {
                        self.isPolling = false
                        return
                    }
                    
                    let fromTag = EthereumQuantityTag(tagType: .block(fromBlock))
                    let toTag = EthereumQuantityTag(tagType: .block(latestBlock))
                    
                    self.eth.getLogs(addresses: self.addresses,
                                     topics: self.topics,
                                     fromBlock: fromTag,
                                     toBlock: toTag) { logsResponse in
                        self.queue.async {
                            defer {
                                self.isPolling = false
                            }
                            
                            switch logsResponse.status {
                            case .success(let newLogs) where !newLogs.isEmpty:
                                self.onLogs(newLogs)
                                self.lastProcessedBlock = latestBlock
                            case .failure(let err):
                                self.onError(err)
                            default:
                                break
                            }
                        }
                    }
                    
                case .failure(let err):
                    self.queue.async {
                        self.isPolling = false
                        self.onError(err)
                        print("\(self.pollerId) finished polling with error: \(err)")
                    }
                }
            }
        }
    }
}
