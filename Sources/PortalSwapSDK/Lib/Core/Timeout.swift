import Foundation

/// TIMING ATTACK: If both HTLCs expire at the same time, the secret holder
/// could wait until the last moment to reveal the secret on the counterparty's
/// chain, claim their funds, but then the counterparty might not have enough
/// time to use the secret before the original HTLC expires. The secret holder
/// would get both sets of funds.
///
/// SOLUTION: The secret holder's HTLC must ALWAYS expire AFTER the
/// counterparty's HTLC, with enough buffer time to account for block times
/// and reorg risks on both chains.
///
/// Example: (Alice is secret holder)
/// - Bob's HTLC expires at 12:00 (he gets Alice's funds if secret revealed)
/// - Alice's HTLC expires at 13:00 (she gets her funds back if no secret)
/// - Alice must reveal secret before 12:00 to claim Bob's funds
/// - This gives Bob 1 hour to safely use the secret before Alice's expires

struct ChainParams {
    let avgBlockTime: Double // in seconds
    let safetyDepth: Int // reorg depth or safety buffer in blocks
}

struct ValidationResult {
    let isValid: Bool
    let reason: String?
    let requiredSafetyBuffer: Double
    let actualBuffer: Double
}

// Chain configurations
let CHAIN_PARAMS: [String: ChainParams] = [
    "lightning": ChainParams(
        avgBlockTime: 600, // Bitcoin block time: 10 minutes
        safetyDepth: 18 // Max CLTV delta for safety
    ),
    "ethereum": ChainParams(
        avgBlockTime: 12, // ~12 seconds
        safetyDepth: 6 // Conservative reorg protection
    ),
    "solana": ChainParams(
        avgBlockTime: 0.4, // ~400ms
        safetyDepth: 32 // Higher due to faster blocks and potential reorgs
    )
]

// Buffer for swap setup: order matching, tx creation, submission
let PROPAGATION_BUFFER: Double = 600 // 10 minutes

/// Secret holder calculates BOTH timeouts upfront based on chain safety requirements
///
/// Timeline:
/// 1. Holder locks funds first (confirmed in holderSafetyDepth)
/// 2. Seeker sees it, locks funds (confirmed in seekerSafetyDepth)
/// 3. Holder reveals secret on seeker's chain (confirmed in seekerSafetyDepth)
/// 4. Seeker sees secret, claims on holder's chain (needs: seekerSafetyDepth + holderSafetyDepth)
func calculateSwapTimeoutBlocks(
    secretHolderChain: String,
    secretSeekerChain: String
) -> (secretHolderTimeoutBlocks: Int, secretSeekerTimeoutBlocks: Int) {
    print(getSafetyBufferBreakdown(myChain: secretHolderChain, theirChain: secretSeekerChain))

    guard let holderParams = CHAIN_PARAMS[secretHolderChain] else {
        fatalError("Unknown chain: \(secretHolderChain)")
    }
    guard let seekerParams = CHAIN_PARAMS[secretSeekerChain] else {
        fatalError("Unknown chain: \(secretSeekerChain)")
    }

    let holderChainSafetyTime = holderParams.avgBlockTime * Double(holderParams.safetyDepth)
    let seekerChainSafetyTime = seekerParams.avgBlockTime * Double(seekerParams.safetyDepth)

    // Seeker timeout: time for holder to reveal after seeker locks
    let secretSeekerTimeout = PROPAGATION_BUFFER + seekerChainSafetyTime

    // Gap must include PROPAGATION_BUFFER to account for delay between locks
    let requiredGap = PROPAGATION_BUFFER + seekerChainSafetyTime + holderChainSafetyTime

    // Holder timeout: seeker timeout + gap
    let secretHolderTimeout = secretSeekerTimeout + requiredGap

    return (
        secretHolderTimeoutBlocks: Int(ceil(secretHolderTimeout / holderParams.avgBlockTime)),
        secretSeekerTimeoutBlocks: Int(ceil(secretSeekerTimeout / seekerParams.avgBlockTime))
    )
}

/// Validates HTLC timeout relationship for atomic swaps using absolute block heights
func validateCounterpartyTimeout(
    myTimeoutBlock: UInt64,
    theirTimeoutBlock: UInt64,
    myCurrentBlock: UInt64,
    theirCurrentBlock: UInt64,
    isSecretHolder: Bool,
    myChain: String,
    theirChain: String
) -> ValidationResult {
    guard let myChainParams = CHAIN_PARAMS[myChain] else {
        return ValidationResult(
            isValid: false,
            reason: "Unknown chain: \(myChain)",
            requiredSafetyBuffer: 0,
            actualBuffer: 0
        )
    }
    guard let theirChainParams = CHAIN_PARAMS[theirChain] else {
        return ValidationResult(
            isValid: false,
            reason: "Unknown chain: \(theirChain)",
            requiredSafetyBuffer: 0,
            actualBuffer: 0
        )
    }

    // Calculate remaining blocks
    let myRemainingBlocks = Int64(myTimeoutBlock) - Int64(myCurrentBlock)
    let theirRemainingBlocks = Int64(theirTimeoutBlock) - Int64(theirCurrentBlock)

    // Convert to time (seconds) for cross-chain comparison
    let myTimeoutSeconds = Double(myRemainingBlocks) * myChainParams.avgBlockTime
    let theirTimeoutSeconds = Double(theirRemainingBlocks) * theirChainParams.avgBlockTime

    if isSecretHolder {
        let requiredSafetyBufferSeconds = myChainParams.avgBlockTime * Double(myChainParams.safetyDepth)

        // As secret holder, my timeout MUST be AFTER theirs (in wall-clock time)
        let actualBufferSeconds = myTimeoutSeconds - theirTimeoutSeconds

        if myRemainingBlocks <= 0 {
            return ValidationResult(
                isValid: false,
                reason: "My timeout has already expired",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        if theirRemainingBlocks <= 0 {
            return ValidationResult(
                isValid: false,
                reason: "Counterparty's timeout has already expired",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        if myTimeoutSeconds <= theirTimeoutSeconds {
            return ValidationResult(
                isValid: false,
                reason: "Secret holder's timeout must be after counterparty's timeout",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        if actualBufferSeconds < requiredSafetyBufferSeconds {
            return ValidationResult(
                isValid: false,
                reason: "Insufficient safety buffer. Required: \(Int(requiredSafetyBufferSeconds))s (\(Int(round(requiredSafetyBufferSeconds / 60)))min), Actual: \(Int(round(actualBufferSeconds)))s (\(Int(round(actualBufferSeconds / 60)))min)",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        return ValidationResult(
            isValid: true,
            reason: nil,
            requiredSafetyBuffer: requiredSafetyBufferSeconds,
            actualBuffer: actualBufferSeconds
        )
    } else {
        let requiredSafetyBufferSeconds = theirChainParams.avgBlockTime * Double(theirChainParams.safetyDepth)

        // As non-secret holder, my timeout MUST be BEFORE theirs (in wall-clock time)
        let actualBufferSeconds = theirTimeoutSeconds - myTimeoutSeconds

        if myRemainingBlocks <= 0 {
            return ValidationResult(
                isValid: false,
                reason: "My timeout has already expired",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        if theirRemainingBlocks <= 0 {
            return ValidationResult(
                isValid: false,
                reason: "Counterparty's timeout has already expired",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        if theirTimeoutSeconds <= myTimeoutSeconds {
            return ValidationResult(
                isValid: false,
                reason: "Non-secret holder's timeout must be before secret holder's timeout",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        if actualBufferSeconds < requiredSafetyBufferSeconds {
            return ValidationResult(
                isValid: false,
                reason: "Insufficient safety buffer. Required: \(Int(requiredSafetyBufferSeconds))s (\(Int(round(requiredSafetyBufferSeconds / 60)))min), Actual: \(Int(round(actualBufferSeconds)))s (\(Int(round(actualBufferSeconds / 60)))min)",
                requiredSafetyBuffer: requiredSafetyBufferSeconds,
                actualBuffer: actualBufferSeconds
            )
        }

        return ValidationResult(
            isValid: true,
            reason: nil,
            requiredSafetyBuffer: requiredSafetyBufferSeconds,
            actualBuffer: actualBufferSeconds
        )
    }
}

/// Get human-readable safety buffer breakdown
func getSafetyBufferBreakdown(
    myChain: String,
    theirChain: String
) -> [String: Any] {
    guard let myParams = CHAIN_PARAMS[myChain],
          let theirParams = CHAIN_PARAMS[theirChain] else {
        return [
            "error": "Unknown chain: \(myChain) or \(theirChain)"
        ]
    }

    let myChainSafety = myParams.avgBlockTime * Double(myParams.safetyDepth)
    let theirChainSafety = theirParams.avgBlockTime * Double(theirParams.safetyDepth)
    let total = myChainSafety + theirChainSafety

    let breakdown = "\(myChain): \(Int(myChainSafety))s (\(myParams.safetyDepth) × \(Int(myParams.avgBlockTime))s), \(theirChain): \(Int(theirChainSafety))s (\(theirParams.safetyDepth) × \(Int(theirParams.avgBlockTime))s)"

    return [
        "myChainSafety": myChainSafety,
        "theirChainSafety": theirChainSafety,
        "total": total,
        "breakdown": breakdown
    ]
}
