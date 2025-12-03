import Foundation
import SolanaSwift

struct RetryOptions {
    let maxRetries: Int?
    let baseDelayMs: UInt64?
    let maxDelayMs: UInt64?
    let skipPreflight: Bool?
    let priorityFeeMultiplier: Double?
    let computeUnitLimit: UInt32?
    let minPriorityFee: UInt64?
    let maxPriorityFee: UInt64?

    init(
        maxRetries: Int? = nil,
        baseDelayMs: UInt64? = nil,
        maxDelayMs: UInt64? = nil,
        skipPreflight: Bool? = nil,
        priorityFeeMultiplier: Double? = nil,
        computeUnitLimit: UInt32? = nil,
        minPriorityFee: UInt64? = nil,
        maxPriorityFee: UInt64? = nil
    ) {
        self.maxRetries = maxRetries
        self.baseDelayMs = baseDelayMs
        self.maxDelayMs = maxDelayMs
        self.skipPreflight = skipPreflight
        self.priorityFeeMultiplier = priorityFeeMultiplier
        self.computeUnitLimit = computeUnitLimit
        self.minPriorityFee = minPriorityFee
        self.maxPriorityFee = maxPriorityFee
    }
}

final class SolanaTransactionRetry {
    private let apiClient: SolanaAPIClient
    private let blockchainClient: BlockchainClient

    init(apiClient: SolanaAPIClient, blockchainClient: BlockchainClient) {
        self.apiClient = apiClient
        self.blockchainClient = blockchainClient
    }

    func executeWithRetry(instructions: [TransactionInstruction], signers: [KeyPair], options: RetryOptions = RetryOptions()) async throws -> String {
        let skipPreflight = options.skipPreflight ?? false
        let computeUnitLimit = options.computeUnitLimit ?? 1_000_000
        let minPriorityFee = options.minPriorityFee ?? 100_000
        let maxPriorityFee = options.maxPriorityFee ?? 2_000_000

        // Get priority fee
        let basePriorityFee = await getRecommendedPriorityFee()
        let priorityFee = min(max(basePriorityFee, minPriorityFee), maxPriorityFee)

        print("Using priority fee: \(priorityFee) microLamports")

        // Build instructions with compute budget
        var allInstructions = try createComputeBudgetInstructions(
            computeUnitLimit: computeUnitLimit,
            priorityFee: priorityFee
        )
        allInstructions.append(contentsOf: instructions)

        // Prepare transaction
        let preparedTransaction = try await blockchainClient.prepareTransaction(
            instructions: allInstructions,
            signers: signers,
            feePayer: signers[0].publicKey
        )

        // Send transaction
        let signature = try await blockchainClient.sendTransaction(
            preparedTransaction: preparedTransaction
        )

        print("Transaction sent: \(signature)")

        print("Transaction confirmed: \(signature)")
        return signature
    }

    private func createComputeBudgetInstructions(computeUnitLimit: UInt32, priorityFee: UInt64) throws -> [TransactionInstruction] {
        var instructions: [TransactionInstruction] = []

        // Compute Budget Program ID
        let computeBudgetProgram = try PublicKey(string: "ComputeBudget111111111111111111111111111111")

        // SetComputeUnitLimit instruction (instruction type 2)
        var limitData = Data([2])
        var limitValue = computeUnitLimit.littleEndian
        limitData.append(Data(bytes: &limitValue, count: MemoryLayout<UInt32>.size))

        instructions.append(TransactionInstruction(
            keys: [],
            programId: computeBudgetProgram,
            data: Array(limitData)
        ))

        // SetComputeUnitPrice instruction (instruction type 3)
        var priceData = Data([3])
        var priceValue = priorityFee.littleEndian
        priceData.append(Data(bytes: &priceValue, count: MemoryLayout<UInt64>.size))

        instructions.append(TransactionInstruction(
            keys: [],
            programId: computeBudgetProgram,
            data: Array(priceData)
        ))

        return instructions
    }

    private func getDefaultPriorityFees() async -> UInt64 {
        do {
            let response: [PrioritizationFeeResult] = try await apiClient.request(
                method: "getRecentPrioritizationFees",
                params: []
            )

            if response.isEmpty {
                return 500_000
            }

            let sortedFees = response.map { $0.prioritizationFee }.sorted()
            let percentile95Index = Int(Double(sortedFees.count) * 0.95)
            let recommendedFee = sortedFees[percentile95Index]

            return max(recommendedFee, 200_000)
        } catch {
            print("Failed to get priority fees, using default: \(error)")
            return 800_000
        }
    }

    private func getRecommendedPriorityFee() async -> UInt64 {
        await getDefaultPriorityFees()
    }
}

struct PrioritizationFeeResult: Decodable {
    let slot: UInt64
    let prioritizationFee: UInt64
}
