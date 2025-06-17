import Foundation
import SolanaSwift

class HtlcLogListener {
    private let apiClient: SolanaAPIClient
    private let programId: PublicKey
    private var lastProcessedSignature: String?
    private var pollingTask: Task<Void, Never>?
    private var callback: ((Log) -> Void)?
    private var isMonitoring = false
    
    private let pollingInterval: TimeInterval = 2.0 // seconds
    private let maxSignaturesPerBatch = 20
    
    private let transactionCache = TransactionCache()
    
    struct Log {
        let event: Event
        let signature: String
        let slot: UInt64
    }
    
    enum Event {
        case deposit(DepositEvent)
        case withdraw(WithdrawEvent)
        case lock(LockEvent)
        case unlock(UnlockEvent)
        
        var type: String {
            switch self {
            case .deposit: return "DEPOSIT"
            case .withdraw: return "WITHDRAW"
            case .lock: return "LOCK"
            case .unlock: return "UNLOCK"
            }
        }
    }
    
    private struct DepositEventData: Codable {
        let maker: String
        let token_mint: String
        let amount: UInt64
        let portal_address: String
    }

    private struct WithdrawEventData: Codable {
        let id: String
        let maker: String
        let token_mint: String
        let amount: UInt64
        let portal_address: String
    }

    private struct LockEventData: Codable {
        let secret_hash: String
        let owner_pubkey: String
        let token_mint: String
        let amount: UInt64
        let swap: SwapData
        let is_holder: Bool
    }

    private struct UnlockEventData: Codable {
        let swap: SwapData
        let is_holder: Bool
        let secret: String?
    }

    private struct SwapData: Codable {
        let id: String
    }
    
    class TransactionCache {
        private var processedSignatures = Set<String>()
        private let maxCacheSize = 1000
        
        func hasProcessed(_ signature: String) -> Bool {
            return processedSignatures.contains(signature)
        }
        
        func markProcessed(_ signature: String) {
            processedSignatures.insert(signature)
            
            // Limit cache size by removing old entries
            if processedSignatures.count > maxCacheSize {
                processedSignatures.removeFirst()
            }
        }
    }
    
    init(apiClient: SolanaAPIClient, programId: PublicKey) {
        self.apiClient = apiClient
        self.programId = programId
    }
    
    func monitor(_ callback: @escaping (Log) -> Void) {
        self.callback = callback
        self.isMonitoring = true
        
        pollingTask = Task {
            while isMonitoring {
                await checkForNewTransactions()
                
                // Sleep using Task.sleep which is cancellable
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }
    
    private func checkForNewTransactions() async {
        do {
            let configs = RequestConfiguration(
                limit: maxSignaturesPerBatch,
                until: lastProcessedSignature
            )
            
            let signatures = try await apiClient.getSignaturesForAddress(
                address: programId.base58EncodedString,
                configs: configs
            )
            
            guard !signatures.isEmpty else {
                return
            }
            
            let signatureStrings = signatures.map { $0.signature }
            let statuses = try await apiClient.getSignatureStatuses(
                signatures: signatureStrings,
                configs: nil
            )
            
            let signatureInfoWithStatus = zip(signatures.reversed(), statuses.reversed())
            
            for (signatureInfo, status) in signatureInfoWithStatus {
                if transactionCache.hasProcessed(signatureInfo.signature) {
                    continue
                }
                
                guard let status = status else {
                    continue
                }
                
                guard status.confirmationStatus == "confirmed" || status.confirmationStatus == "finalized" else {
                    continue
                }
                
                if status.err != nil {
                    transactionCache.markProcessed(signatureInfo.signature)
                    lastProcessedSignature = signatureInfo.signature
                    continue
                }
                
                if let transactionInfo = try await apiClient.getTransaction(
                    signature: signatureInfo.signature,
                    commitment: "confirmed"
                ) {
                    processTransaction(
                        signature: signatureInfo.signature,
                        transactionInfo: transactionInfo
                    )
                }
                
                transactionCache.markProcessed(signatureInfo.signature)
                lastProcessedSignature = signatureInfo.signature
            }
        } catch {
            print("Error polling for transactions: \(error)")
        }
    }
    
    private func processTransaction(signature: String, transactionInfo: TransactionInfo) {
        guard let meta = transactionInfo.meta,
              let logMessages = meta.logMessages,
              let slot = transactionInfo.slot else {
            return
        }
        
        // Parse logs to extract program events
        for log in logMessages {
            if log.contains("Program log: DEPOSIT:") {
                if let event = parseDepositFromLog(log) {
                    let logData = Log(
                        event: event,
                        signature: signature,
                        slot: slot
                    )
                    
                    callback?(logData)
                }
            } else if log.contains("Program log: WITHDRAW:") {
                if let event = parseWithdrawFromLog(log) {
                    let logData = Log(
                        event: event,
                        signature: signature,
                        slot: slot
                    )
                    
                    callback?(logData)
                }
            } else if log.contains("Program log: LOCK:") {
                if let event = parseLockFromLog(log) {
                    let logData = Log(
                        event: event,
                        signature: signature,
                        slot: slot
                    )
                    
                    callback?(logData)
                }
            } else if log.contains("Program log: UNLOCK:") {
                if let event = parseUnlockFromLog(log) {
                    let logData = Log(
                        event: event,
                        signature: signature,
                        slot: slot
                    )
                    
                    callback?(logData)
                }
            }
        }
    }

    private func parseDepositFromLog(_ log: String) -> Event? {
        let prefix = "Program log: DEPOSIT: "
        guard log.hasPrefix(prefix) else {
            return nil
        }
        
        let jsonString = String(log.dropFirst(prefix.count))
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let depositData = try decoder.decode(DepositEventData.self, from: jsonData)
            
            return .deposit(
                DepositEvent(
                    token_mint: depositData.token_mint,
                    amount: depositData.amount,
                    maker: depositData.maker,
                    portal_address: depositData.portal_address
                )
            )
        } catch {
            print("Failed to parse deposit event: \(error)")
            print("JSON string: \(jsonString)")
            return nil
        }
    }

    private func parseEventJSON(from log: String, prefix: String) -> String? {
        guard log.contains(prefix) else { return nil }
        
        let components = log.components(separatedBy: prefix)
        guard components.count >= 2 else { return nil }
        
        let jsonPart = components[1...].joined(separator: prefix)
        
        return jsonPart.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseWithdrawFromLog(_ log: String) -> Event? {
        guard let jsonString = parseEventJSON(from: log, prefix: "Program log: WITHDRAW: ") else {
            return nil
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let withdrawData = try decoder.decode(WithdrawEventData.self, from: jsonData)
            
            return .withdraw(
                WithdrawEvent(
                    token_mint: withdrawData.token_mint,
                    amount: withdrawData.amount,
                    maker: withdrawData.maker,
                    portal_address: withdrawData.portal_address,
                    id: withdrawData.id
                )
            )
        } catch {
            print("Failed to parse withdraw event: \(error)")
            return nil
        }
    }

    private func parseLockFromLog(_ log: String) -> Event? {
        guard let jsonString = parseEventJSON(from: log, prefix: "Program log: LOCK: ") else {
            return nil
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let lockData = try decoder.decode(LockEventData.self, from: jsonData)
            
            return .lock(
                LockEvent(
                    swap: SwapInfo(id: lockData.swap.id),
                    is_holder: lockData.is_holder,
                    secret_hash: lockData.secret_hash,
                    owner_pubkey: lockData.owner_pubkey,
                    token_mint: lockData.token_mint,
                    amount: lockData.amount
                )
            )
        } catch {
            print("Failed to parse lock event: \(error)")
            return nil
        }
    }

    private func parseUnlockFromLog(_ log: String) -> Event? {
        guard let jsonString = parseEventJSON(from: log, prefix: "Program log: UNLOCK: ") else {
            return nil
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let unlockData = try decoder.decode(UnlockEventData.self, from: jsonData)
            
            return .unlock(
                UnlockEvent(
                    swap: SwapInfo(id: unlockData.swap.id),
                    is_holder: unlockData.is_holder,
                    secret: unlockData.secret ?? ""
                )
            )
        } catch {
            print("Failed to parse unlock event: \(error)")
            return nil
        }
    }
    
    func cleanup() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        callback = nil
    }
}
