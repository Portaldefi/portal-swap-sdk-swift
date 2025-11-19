import Foundation
import SolanaSwift

class HtlcLogListener: BaseClass {
    private let apiClient: SolanaAPIClient
    private let programId: PublicKey
    private var lastFinalizedSlot: UInt64
    private var pollingTask: Task<Void, Never>?
    private var callback: ((Log) -> Void)?
    private var isProcessing = false

    private let pollingInterval: TimeInterval = 3.0
    private let slotsBehind: UInt64 = 30

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
        let amount: Int64
        let portal_address: String
    }

    private struct WithdrawEventData: Codable {
        let id: String
        let maker: String
        let token_mint: String
        let amount: Int64
        let portal_address: String
    }

    private struct LockEventData: Codable {
        let secret_hash: String
        let owner_pubkey: String
        let token_mint: String
        let amount: Int64
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

    init(apiClient: SolanaAPIClient, programId: PublicKey, initialSlot: UInt64 = 0) {
        self.apiClient = apiClient
        self.programId = programId
        self.lastFinalizedSlot = initialSlot

        super.init(id: "solana-event-listener")
    }

    func startPolling(_ callback: @escaping (Log) -> Void) {
        self.callback = callback

        info("Starting slot subscription from slot \(lastFinalizedSlot) with \(slotsBehind) confirmations")

        pollingTask = Task {
            while !Task.isCancelled {
                await processNewSlots()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }

    private func processNewSlots() async {
        guard !isProcessing else { return }

        isProcessing = true
        defer { isProcessing = false }

        let currentSlot = await getCurrentSlot()
        let confirmedSlot = currentSlot > slotsBehind ? currentSlot - slotsBehind : 0

        guard confirmedSlot > lastFinalizedSlot else {
            return
        }

        info("Processing slots \(lastFinalizedSlot + 1) to \(confirmedSlot)")

        for slot in (lastFinalizedSlot + 1)...confirmedSlot {
            await processSlot(slot)
            lastFinalizedSlot = slot
        }
    }

    private func processSlot(_ slot: UInt64) async {
        do {
            let configs = RequestConfiguration(encoding: "jsonParsed")

            let signatures = try await apiClient.getSignaturesForAddress(
                address: programId.base58EncodedString,
                configs: configs
            )

            guard !signatures.isEmpty else { return }

            for signatureInfo in signatures.reversed() {
                guard let transactionSlot = signatureInfo.slot else { continue }

                if transactionSlot != slot {
                    continue
                }

                if signatureInfo.err != nil {
                    continue
                }

                if let transactionInfo = try await apiClient.getTransaction(
                    signature: signatureInfo.signature,
                    commitment: "confirmed"
                ) {
                    processTransaction(
                        signature: signatureInfo.signature,
                        transactionInfo: transactionInfo,
                        slot: slot
                    )
                }
            }
        } catch {
            self.error("Error processing slot \(slot):", error)
        }
    }

    private func getCurrentSlot() async -> UInt64 {
        do {
            return try await apiClient.getSlot()
        } catch {
            self.error("Error getting current slot:", error)
            return lastFinalizedSlot
        }
    }

    private func processTransaction(signature: String, transactionInfo: TransactionInfo, slot: UInt64) {
        guard let meta = transactionInfo.meta,
              let logMessages = meta.logMessages else {
            return
        }

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
            self.error("Failed to parse deposit event:", error)
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
            self.error("Failed to parse withdraw event:", error)
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
            self.error("Failed to parse lock event:", error)
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
            self.error("Failed to parse unlock event:", error)
            return nil
        }
    }

    func cleanup() {
        pollingTask?.cancel()
        pollingTask = nil
        callback = nil
        info("Stopped slot subscription")
    }
}
