import Foundation
import Web3ContractABI
import Web3
import BigInt
import Promises

struct ProcessedLog {
    let eventName: String
    let args: [String: Any]
    let transactionHash: String
    let blockNumber: BigUInt
    let logIndex: BigUInt
}

struct ContractConfig {
    let address: EthereumAddress
    let events: [SolidityEvent]
}

class ContractEventListener: BaseClass {
    private var lastProcessedBlock: BigUInt
    private let web3: Web3
    private let contracts: [ContractConfig]
    private let confirmations: Int
    private var timer: DispatchSourceTimer?
    private var isProcessing: Bool = false
    private let pollingInterval: TimeInterval = 3.0

    private let queue = DispatchQueue(label: "ethereum.event.listener", qos: .utility)

    init(
        web3: Web3,
        contracts: [ContractConfig],
        initialBlock: BigUInt = 0,
        confirmations: Int = 30
    ) {
        self.web3 = web3
        self.contracts = contracts
        self.lastProcessedBlock = initialBlock
        self.confirmations = confirmations

        super.init(id: "ethereum-event-listener")
    }

    func startPolling(callback: @escaping (ProcessedLog) -> Void) {
        info("Starting block subscription from block \(lastProcessedBlock) with \(confirmations) confirmations")

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: pollingInterval)

        newTimer.setEventHandler { [weak self] in
            guard let self = self else { return }

            Task {
                await self.processNewBlocks(callback: callback)
            }
        }

        timer = newTimer
        newTimer.resume()
    }

    private func processNewBlocks(callback: @escaping (ProcessedLog) -> Void) async {
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let currentBlock = try await getCurrentBlockNumber()
            let confirmedBlock = currentBlock - BigUInt(confirmations)

            guard confirmedBlock > lastProcessedBlock else {
                return
            }

            info("Processing blocks \(lastProcessedBlock + 1) to \(confirmedBlock) (confirmations: \(confirmations))")

            for block in stride(from: lastProcessedBlock + 1, through: confirmedBlock, by: 1) {
                try await processBlockAtHeight(block, callback: callback)
                lastProcessedBlock = block
            }
        } catch {
            self.error("Error processing blocks:", error)
        }
    }

    private func processBlockAtHeight(_ blockNumber: BigUInt, callback: @escaping (ProcessedLog) -> Void) async throws {
        let fromTag = EthereumQuantityTag(tagType: .block(blockNumber))
        let toTag = EthereumQuantityTag(tagType: .block(blockNumber))

        let addresses = contracts.map { $0.address }

        let logs = try await getLogsAsync(addresses: addresses, fromBlock: fromTag, toBlock: toTag)

        for log in logs {
            await processLog(log, callback: callback)
        }
    }

    private func processLog(_ log: EthereumLogObject, callback: @escaping (ProcessedLog) -> Void) async {
        guard let txHash = log.transactionHash?.hex(),
              let blockNumber = log.blockNumber?.quantity,
              let logIndex = log.logIndex?.quantity else {
            return
        }

        guard let contract = contracts.first(where: {
            $0.address.hex(eip55: false).lowercased() == log.address.hex(eip55: false).lowercased()
        }) else {
            warn("No contract found for address \(log.address.hex(eip55: false))")
            return
        }

        guard let topic0 = log.topics.first else { return }

        for event in contract.events {
            if event.topic == topic0 {
                do {
                    let decoded = try ABI.decodeLog(event: event, from: log)

                    let processedLog = ProcessedLog(
                        eventName: event.name,
                        args: decoded,
                        transactionHash: txHash,
                        blockNumber: blockNumber,
                        logIndex: logIndex
                    )

                    callback(processedLog)
                } catch {
                    self.error("Error processing log:", error, log)
                }
                break
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        info("Stopped block subscription")
    }

    func getLastProcessedBlock() -> BigUInt {
        return lastProcessedBlock
    }

    private func getCurrentBlockNumber() async throws -> BigUInt {
        return try await withCheckedThrowingContinuation { continuation in
            web3.eth.blockNumber { response in
                switch response.status {
                case .success(let blockNumber):
                    continuation.resume(returning: blockNumber.quantity)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func getLogsAsync(
        addresses: [EthereumAddress],
        fromBlock: EthereumQuantityTag,
        toBlock: EthereumQuantityTag
    ) async throws -> [EthereumLogObject] {
        return try await withCheckedThrowingContinuation { continuation in
            web3.eth.getLogs(
                addresses: addresses,
                topics: nil,
                fromBlock: fromBlock,
                toBlock: toBlock
            ) { response in
                switch response.status {
                case .success(let logs):
                    continuation.resume(returning: logs)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
