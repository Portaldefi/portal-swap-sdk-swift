import Foundation
import SolanaSwift

/// Utility function to create instructions for wrapping SOL into wSOL (Wrapped SOL) token account
/// This creates the necessary instructions to:
/// 1. Create associated token account if it doesn't exist
/// 2. Transfer SOL to the token account
/// 3. Sync the native balance
///
/// - Parameters:
///   - apiClient: The Solana API client for checking account existence
///   - keyPair: The keypair of the account owner
///   - tokenMint: The mint address of the token (should be NATIVE_MINT for SOL)
///   - tokenAccount: The associated token account address
///   - amount: The amount of lamports to wrap
///   - isSOL: Flag indicating if this is SOL (for determining token program ID)
/// - Returns: Array of transaction instructions to wrap SOL
func createWrapSolInstructions(apiClient: SolanaAPIClient, keyPair: KeyPair, tokenMint: PublicKey, tokenAccount: PublicKey, amount: UInt64, isSOL: Bool) async throws -> [TransactionInstruction] {
    var instructions: [TransactionInstruction] = []

    // Check if the token account already exists
    let accountInfoResult: BufferInfo<TokenAccountState>? = try await apiClient.getAccountInfo(account: tokenAccount.base58EncodedString)
    let accountExists = accountInfoResult != nil

    // If account doesn't exist, create it first
    if !accountExists {
        let createATAInstruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
            mint: tokenMint,
            owner: keyPair.publicKey,
            payer: keyPair.publicKey,
            tokenProgramId: Solana.tokenProgramId(isSOL: isSOL)
        )
        instructions.append(createATAInstruction)
    }

    // Add SOL transfer instruction
    let transferInstruction = SystemProgram.transferInstruction(
        from: keyPair.publicKey,
        to: tokenAccount,
        lamports: amount
    )
    instructions.append(transferInstruction)

    // Add sync native instruction to update the wSOL balance
    let syncNativeInstructionData: [UInt8] = [17]
    let syncNativeInstruction = TransactionInstruction(
        keys: [
            AccountMeta(publicKey: tokenAccount, isSigner: false, isWritable: true)
        ],
        programId: Solana.TOKEN_PROGRAM_ID,
        data: syncNativeInstructionData
    )
    instructions.append(syncNativeInstruction)

    return instructions
}
