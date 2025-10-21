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
    private var timer: DispatchSourceTimer?
    private var lastProcessedBlock: BigUInt?
    private var isPolling: Bool = false
    
    private var lastProcessedEthBlock: BigUInt {
        set {
            UserDefaults.standard.setValue(Int(newValue), forKey: "\(pollerId)_lastProcessedBlock")
        }
        get {
            return BigUInt(UserDefaults.standard.integer(forKey: "\(pollerId)_lastProcessedBlock"))
        }
    }
    
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
    
    deinit {
        stopPolling()
    }
    
    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        
        // Create dispatch timer that works on any queue without requiring a run loop
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + interval, repeating: interval)
        
        newTimer.setEventHandler { [weak self] in
            self?.pollLogs()
        }
        
        self.timer = newTimer
        newTimer.resume()
    }
    
    /// Stops the polling process.
    func stopPolling() {
//        lastProcessedBlock = nil
        timer?.cancel()
        timer = nil
    }
    
    /// Polls for new logs.
    /// This method first gets the latest block number, determines the range to query,
    /// and then calls `eth.getLogs` to retrieve logs in that range.
    private func pollLogs() {
        guard !self.isPolling else { return }
        
        self.isPolling = true
        
        self.eth.blockNumber { [weak self] response in
            guard let self = self else { return }
                        
            switch response.status {
            case .success(let latest):
                let latestBlock = latest.quantity
                
                let fromBlock: BigUInt

                if pollerId.contains("Ethereum") {
//                    print("\(pollerId) latest block - \(latestBlock)")
                    
                    if lastProcessedBlock == 0 {
                        fromBlock = latestBlock
                        lastProcessedEthBlock = latestBlock
                    } else {
                        if lastProcessedEthBlock + 5 < latestBlock {
                            fromBlock = latestBlock
                            lastProcessedEthBlock = latestBlock
                        } else {
                            fromBlock = lastProcessedEthBlock + 1
                        }
                    }
                    
//                    print("\(pollerId) from block - \(fromBlock)")
                } else {
                    // compute fromBlock under the queue
                    if let last = self.lastProcessedBlock {
                        fromBlock = last + 1
                    } else {
                        // On first run, start from current block to avoid processing old events
                        fromBlock = latestBlock
                    }
                }
                                            
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
                    
                    if self.pollerId.contains("Ethereum") {
                        self.lastProcessedEthBlock = latestBlock
                    } else {
                        self.lastProcessedBlock = latestBlock
                    }
                    
                    self.queue.async {
                        defer {
                            self.isPolling = false
                        }
                                                
                        switch logsResponse.status {
                        case .success(let newLogs):
                            if !newLogs.isEmpty {
                                self.onLogs(newLogs)
                            }
                        case .failure(let err):
                            self.onError(err)
                        }
                    }
                }
                
            case .failure(let err):
                self.queue.async {
                    self.isPolling = false
                    self.onError(err)
                }
            }
        }
    }
}
