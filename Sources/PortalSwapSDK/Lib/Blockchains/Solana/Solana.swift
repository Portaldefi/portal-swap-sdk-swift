import Foundation
import Crypto
import BigInt
import Promises
import SolanaSwift

struct DepositEvent {
    let token_mint: String
    let amount: UInt64
    let maker: String
    let portal_address: String
}

struct WithdrawEvent {
    let token_mint: String
    let amount: UInt64
    let maker: String
    let portal_address: String
    let id: String
}

struct LockEvent {
    let swap: SwapInfo
    let is_holder: Bool
    let secret_hash: String
    let owner_pubkey: String
    let token_mint: String
    let amount: UInt64
}

struct UnlockEvent {
    let swap: SwapInfo
    let is_holder: Bool
    let secret: String
}

struct SwapInfo {
    let id: String
}

final class Solana: BaseClass, NativeChain {
    enum Step: String {
        case lock = "lock"
        case unlock = "unlock"
    }
    
    private let NATIVE_MINT = try! PublicKey(string: "So11111111111111111111111111111111111111112")
    private let TOKEN_PROGRAM_ID = try! PublicKey(string: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    private let TOKEN_2022_PROGRAM_ID = try! PublicKey(string: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
    
    private let keyPair: KeyPair
    private let apiClient: SolanaAPIClient
    private let blockchainClient: BlockchainClient
    private let programId: PublicKey
    
    private let logPoller: HtlcLogListener
    
    var address: String {
        keyPair.publicKey.base58EncodedString
    }
    
    init(props: SwapSdkConfig.Blockchains.Solana) {
        self.keyPair = props.keyPair

        if let provider = props.provider {
            self.apiClient = provider.apiClient
            self.blockchainClient = provider
        } else {
            let endpoint = APIEndPoint(
                address: props.rpcUrl,
                network: .devnet
            )
            let jsonRpcClient = JSONRPCAPIClient(endpoint: endpoint)
            self.apiClient = jsonRpcClient
            self.blockchainClient = BlockchainClient(apiClient: apiClient)
        }
        
        self.programId = try! PublicKey(string: props.programId)
        self.logPoller = HtlcLogListener(apiClient: apiClient, programId: programId)
                
        super.init(id: "solana")
    }
    
    func start() async throws {
        logPoller.monitor { [weak self] log in
            guard let self else { return }
            
            switch log.event {
            case .deposit(let depositEvent):
                let liquidity = self.liquidityArgs(event: depositEvent, signature: log.signature, slot: log.slot)
                self.info("deposit", liquidity)
                self.emit(event: "deposit", args: [liquidity])
            case .withdraw(let withdrawEvent):
                let liquidity = self.liquidityArgs(event: withdrawEvent, signature: log.signature, slot: log.slot)
                self.info("withdraw", liquidity)
                self.emit(event: "withdraw", args: [liquidity])
            case .lock(let lockEvent):
                let (event, swapDiff) = self.swapArgs(event: lockEvent, signature: log.signature, step: .lock)
                self.info(event, swapDiff)
                self.emit(event: event, args: [swapDiff])
            case .unlock(let unlockEvent):
                let (event, swapDiff) = self.swapArgs(event: unlockEvent, signature: log.signature, step: .unlock)
                self.info(event, swapDiff)
                self.emit(event: event, args: [swapDiff])
            }
        }
    }
    
    func stop() async throws {
        await logPoller.cleanup()
    }
    
    func deposit(_ liquidity: Liquidity) -> Promise<Liquidity> {
        Promise { fulfill, reject in
            Task { [weak self] in
                guard let self else {
                    return reject(SdkError.instanceUnavailable())
                }
                
                do {
                    let assetAddress = liquidity.contractAddress
                    let isSOL = liquidity.symbol == "SOL"
                    
                    if isSOL {
                        try await wrapSol(liquidity.nativeAmount)
                    }
                    
                    let (fund, vault) = try getFundAndVault(assetAddress: assetAddress, isSOL: isSOL)
                    let makerTokenAccount = try getMyAssociatedTokenAddress(
                        assetAddress: assetAddress,
                        isSOL: isSOL
                    )
                    
                    let method = "global:deposit"
                    let methodData = Data(method.utf8)
                    let hash = SHA256.hash(data: methodData)
                    let discriminator = Array(hash.prefix(8))
                    
                    let accounts = [
                        AccountMeta(publicKey: keyPair.publicKey, isSigner: true, isWritable: true),
                        AccountMeta(publicKey: try PublicKey(string: assetAddress), isSigner: false, isWritable: false),
                        AccountMeta(publicKey: makerTokenAccount, isSigner: false, isWritable: true),
                        AccountMeta(publicKey: fund, isSigner: false, isWritable: true),
                        AccountMeta(publicKey: vault, isSigner: false, isWritable: true),
                        AccountMeta(publicKey: AssociatedTokenProgram.id, isSigner: false, isWritable: false),
                        AccountMeta(publicKey: tokenProgramId(isSOL: isSOL), isSigner: false, isWritable: false),
                        AccountMeta(publicKey: SystemProgram.id, isSigner: false, isWritable: false)
                    ]
                    
                    self.debug("deposit.starting", [
                        "contract": ["name": "hashtimelock", "address": assetAddress],
                        "fund": fund.base58EncodedString,
                        "vault": vault.base58EncodedString,
                        "amount": liquidity.nativeAmount,
                        "portalAddress": liquidity.portalAddress
                    ])
                    
                    var data = Data(discriminator)
                    
                    // Append amount as 8 bytes (equivalent to BN in TypeScript)
                    let amountValue = UInt64(truncatingIfNeeded: liquidity.nativeAmount)
                    var amountBytes = amountValue.littleEndian
                    data.append(Data(bytes: &amountBytes, count: MemoryLayout<UInt64>.size))
                    
                    // Append portal address as a string with length prefix
                    let portalAddressData = liquidity.portalAddress.data(using: .utf8)!
                    var portalAddressLength = UInt32(portalAddressData.count).littleEndian
                    data.append(Data(bytes: &portalAddressLength, count: MemoryLayout<UInt32>.size))
                    data.append(portalAddressData)
                    
                    let instruction = TransactionInstruction(
                        keys: accounts,
                        programId: programId,
                        data: Array(data)
                    )
                    
                    let preparedTransaction = try await blockchainClient.prepareTransaction(
                        instructions: [instruction],
                        signers: [keyPair],
                        feePayer: keyPair.publicKey
                    )
                    
                    let txSignature = try await blockchainClient.sendTransaction(
                        preparedTransaction: preparedTransaction
                    )
                    
                    liquidity.id = "0x\(txSignatureToHex(txSignature))"
                    liquidity.nativeReceipt = txSignature
                    
                    self.info("deposit", ["liquidity": liquidity])
                    fulfill(liquidity)
                } catch {
                    self.error("deposit", error, ["liquidity": liquidity])
                    reject(NativeChainError.unexpected(cause: error))
                }
            }
        }
    }
    
    func withdraw(_ liquidity: Liquidity) -> Promises.Promise<Liquidity> {
        Promise {
            
        }
    }
    
    func createInvoice(_ party: Party) -> Promises.Promise<Invoice> {
        Promise { fulfill, reject in
            Task { [weak self] in
                guard let self else {
                    return reject(SdkError.instanceUnavailable())
                }
                
                do {
                    let isSOL = party.symbol == "SOL"
                    let hash = Data(hex: party.swap!.secretHash)
                    let invoice = try invoiceAddress(hash: hash)

                    let discriminator: [UInt8] = [154, 170, 31, 135, 134, 100, 156, 146]
                    
                    let accounts = [
                        // 1. signer
                        AccountMeta(publicKey: keyPair.publicKey, isSigner: true, isWritable: true),
                        
                        // 2. tokenMint
                        AccountMeta(publicKey: try PublicKey(string: party.contractAddress), isSigner: false, isWritable: false),
                        
                        // 3. invoice
                        AccountMeta(publicKey: invoice, isSigner: false, isWritable: true),
                        
                        // 4. associatedTokenProgram - with explicit address
                        AccountMeta(publicKey: try PublicKey(string: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
                                    isSigner: false, isWritable: false),
                        
                        // 5. tokenProgram
                        AccountMeta(publicKey: tokenProgramId(isSOL: isSOL), isSigner: false, isWritable: false),
                        
                        // 6. systemProgram - with explicit address
                        AccountMeta(publicKey: try PublicKey(string: "11111111111111111111111111111111"),
                                    isSigner: false, isWritable: false)
                    ]
                    
                    let swapToSend = "{\"id\":\"\(party.swap!.id)\"}"
                    
                    self.debug("createInvoice.starting", [
                        "contract": ["name": "hashtimelock", "address": party.contractAddress],
                        "invoice": invoice.base58EncodedString,
                        "amount": party.amount,
                        "swapToSend": swapToSend
                    ])
                    
                    var data = Data(discriminator)
                    data.append(hash)
                    
                    let amountValue = UInt64(truncatingIfNeeded: party.amount)
                    var amountBytes = amountValue.littleEndian
                    data.append(Data(bytes: &amountBytes, count: MemoryLayout<UInt64>.size))
                    
                    let swapData = swapToSend.data(using: .utf8)!
                    var swapDataLength = UInt32(swapData.count).littleEndian
                    data.append(Data(bytes: &swapDataLength, count: MemoryLayout<UInt32>.size))
                    data.append(swapData)
                    
                    let instruction = TransactionInstruction(
                        keys: accounts,
                        programId: programId,
                        data: Array(data)
                    )
                    
                    let preparedTransaction = try await blockchainClient.prepareTransaction(
                        instructions: [instruction],
                        signers: [keyPair],
                        feePayer: keyPair.publicKey
                    )
                    
                    let _ = try await blockchainClient.sendTransaction(
                        preparedTransaction: preparedTransaction
                    )
                    
                    party.invoice = invoice.base58EncodedString
                    
                    self.info("createInvoice", party)
                    fulfill(invoice.base58EncodedString)
                } catch {
                    self.error("createInvoice", error)
                    reject(error)
                }
            }
        }
    }
    
    func payInvoice(_ party: Party) -> Promise<Void> {
        Promise { fulfill, reject in
            Task { [weak self] in
                guard let self else {
                    return reject(SdkError.instanceUnavailable())
                }
                
                do {
                    guard let invoice = party.invoice else {
                        throw SwapSDKError.msg("invoice not set")
                    }
                    
                    let invoicePubkey = try PublicKey(string: invoice)
                    let inv = try await apiClient.fetchInvoice(at: invoicePubkey)
                    
                    let isSOL = party.symbol == "SOL"
                    if isSOL {
                        try await wrapSol(BigInt(party.amount))
                    }
                    
                    let hash = Data(hex: party.swap!.secretHash)
                    
                    let (htl, purse) = try getHtlAndPurse(
                        hash: hash,
                        assetAddress: party.contractAddress,
                        nativeAddress: keyPair.publicKey,
                        isSOL: isSOL
                    )
                    
                    let tokenMint = try PublicKey(string: party.contractAddress)
                    let taker = try PublicKey(string: inv.payeePubkey.base58EncodedString)
                    let takerTokenAccount = try PublicKey.associatedTokenAddress(
                        walletAddress: taker,
                        tokenMintAddress: tokenMint,
                        tokenProgramId: tokenProgramId(isSOL: isSOL)
                    )
                    
                    let accounts = [
                        // maker
                        AccountMeta(publicKey: keyPair.publicKey, isSigner: true, isWritable: true),
                        // tokenMint
                        AccountMeta(publicKey: tokenMint, isSigner: false, isWritable: false),
                        // makerTokenAccount
                        AccountMeta(publicKey: try getMyAssociatedTokenAddress(
                            assetAddress: party.contractAddress,
                            isSOL: isSOL
                        ), isSigner: false, isWritable: true),
                        // taker
                        AccountMeta(publicKey: taker, isSigner: false, isWritable: false),
                        // takerTokenAccount
                        AccountMeta(publicKey: takerTokenAccount, isSigner: false, isWritable: false),
                        // invoice
                        AccountMeta(publicKey: invoicePubkey, isSigner: false, isWritable: true),
                        // htl
                        AccountMeta(publicKey: htl, isSigner: false, isWritable: true),
                        // purse
                        AccountMeta(publicKey: purse, isSigner: false, isWritable: true),
                        // associatedTokenProgram
                        AccountMeta(publicKey: try PublicKey(string: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
                                   isSigner: false, isWritable: false),
                        // tokenProgram
                        AccountMeta(publicKey: tokenProgramId(isSOL: isSOL), isSigner: false, isWritable: false),
                        //systemProgram
                        AccountMeta(publicKey: try PublicKey(string: "11111111111111111111111111111111"),
                                   isSigner: false, isWritable: false)
                    ]
                    
                    let isHolderOnSolana = party.swap?.secretHolder.chain == "solana"
                    let swapToSend = "{\"id\":\"0x\(party.swap!.id)\"}"
                    
                    self.debug("payInvoice.starting", [
                        "contract": ["name": "hashtimelock", "address": party.contractAddress],
                        "invoice": invoicePubkey.base58EncodedString,
                        "htl": htl.base58EncodedString,
                        "purse": purse.base58EncodedString,
                        "taker": taker.base58EncodedString,
                        "takerTokenAccount": takerTokenAccount.base58EncodedString,
                        "amount": "\(party.amount)",
                        "swapToSend": swapToSend,
                        "isHolderOnSolana": "\(isHolderOnSolana)"
                    ])
                    

                    let discriminator: [UInt8] = [21, 19, 208, 43, 237, 62, 255, 87]
                    
                    var data = Data(discriminator)
                    data.append(hash)
                    
                    let amountValue = UInt64(truncatingIfNeeded: party.amount)
                    var amountBytes = amountValue.littleEndian
                    data.append(Data(bytes: &amountBytes, count: MemoryLayout<UInt64>.size))
                    
                    let durationValue = UInt64(1000000)
                    var durationBytes = durationValue.littleEndian
                    data.append(Data(bytes: &durationBytes, count: MemoryLayout<UInt64>.size))
                    
                    let swapData = swapToSend.data(using: .utf8)!
                    var swapDataLength = UInt32(swapData.count).littleEndian
                    data.append(Data(bytes: &swapDataLength, count: MemoryLayout<UInt32>.size))
                    data.append(swapData)
                    
                    data.append((isHolderOnSolana) ? 1 : 0)
                    
                    let instruction = TransactionInstruction(
                        keys: accounts,
                        programId: programId,
                        data: Array(data)
                    )
                    
                    let preparedTransaction = try await blockchainClient.prepareTransaction(
                        instructions: [instruction],
                        signers: [keyPair],
                        feePayer: keyPair.publicKey
                    )
                    
                    let _ = try await blockchainClient.sendTransaction(
                        preparedTransaction: preparedTransaction
                    )
                    
                    self.info("payInvoice", party)
                    fulfill(())
                } catch let error as NativeChainError {
                    self.error("payInvoice", error)
                    reject(error)
                } catch {
                    self.error("payInvoice", error)
                    reject(error)
                }
            }
        }
    }
    
    func settleInvoice(for party: Party, with secret: Data) -> Promise<Party> {
        Promise { fulfill, reject in
            Task { [weak self] in
                guard let self else {
                    return reject(SdkError.instanceUnavailable())
                }
                
                guard let swap = party.swap else {
                    return reject(SdkError.instanceUnavailable())
                }
                
                guard let invoice = party.invoice else {
                    throw NativeChainError(message: "invoice not set", code: "")
                }
                
                do {
                    let isSOL = party.symbol == "SOL"
                    let hash = Data(hex: swap.secretHash)
                    let invoicePubkey = try PublicKey(string: invoice)
                    
                    let inv = try await apiClient.fetchInvoice(at: invoicePubkey)
                    
                    let maker = inv.payerPubkey
                    
                    let (htl, purse) = try getHtlAndPurse(
                        hash: hash,
                        assetAddress: party.contractAddress,
                        nativeAddress: maker,
                        isSOL: isSOL
                    )
                    
                    let tokenMint = try PublicKey(string: party.contractAddress)
                    let makerTokenAccount = try PublicKey.associatedTokenAddress(
                        walletAddress: maker,
                        tokenMintAddress: tokenMint,
                        tokenProgramId: tokenProgramId(isSOL: isSOL)
                    )
                    
                    let accounts = [
                        // 1. taker
                        AccountMeta(publicKey: keyPair.publicKey, isSigner: true, isWritable: true),
                        
                        // 2. maker
                        AccountMeta(publicKey: maker, isSigner: false, isWritable: true),
                        
                        // 3. tokenMint
                        AccountMeta(publicKey: tokenMint, isSigner: false, isWritable: false),
                        
                        // 4. taker_token_account (ADD THIS - taker's token account, not maker's)
                        AccountMeta(publicKey: try PublicKey.associatedTokenAddress(
                            walletAddress: keyPair.publicKey,  // taker's wallet
                            tokenMintAddress: tokenMint,
                            tokenProgramId: tokenProgramId(isSOL: isSOL)
                        ), isSigner: false, isWritable: true),
                        
                        // 5. htl
                        AccountMeta(publicKey: htl, isSigner: false, isWritable: true),
                        
                        // 6. purse
                        AccountMeta(publicKey: purse, isSigner: false, isWritable: true),
                        
                        // 7. associated_token_program (ADD THIS)
                        AccountMeta(publicKey: try PublicKey(string: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
                                   isSigner: false, isWritable: false),
                        
                        // 8. tokenProgram
                        AccountMeta(publicKey: tokenProgramId(isSOL: isSOL), isSigner: false, isWritable: false),
                        
                        // 9. system_program (ADD THIS)
                        AccountMeta(publicKey: try PublicKey(string: "11111111111111111111111111111111"),
                                   isSigner: false, isWritable: false)
                    ]

                    
                    let swapToSend = "{\"id\":\"0x\(swap.id)\"}"
                    let isHolderOnSolana = swap.secretHolder.chain != "solana"
                    
                    self.debug("settleInvoice.starting", [
                        "contract": ["name": "hashtimelock", "address": party.contractAddress],
                        "htl": htl.base58EncodedString,
                        "purse": purse.base58EncodedString,
                        "maker": maker.base58EncodedString,
                        "makerTokenAccount": makerTokenAccount.base58EncodedString,
                        "amount": party.amount,
                        "swapToSend": swapToSend,
                        "isHolderOnSolana": isHolderOnSolana
                    ])
                    
                    // Create unlock instruction
                    let method = "global:unlock"
                    let methodData = Data(method.utf8)
                    let discriminator = Array(SHA256.hash(data: methodData).prefix(8))
                    
                    var data = Data(discriminator)
                    guard secret.count == 32 else {
                        throw NativeChainError(message: "Secret must be exactly 32 bytes", code: "")
                    }
                    data.append(secret)
                    
                    let swapData = swapToSend.data(using: .utf8)!
                    var swapDataLength = UInt32(swapData.count).littleEndian
                    data.append(Data(bytes: &swapDataLength, count: MemoryLayout<UInt32>.size))
                    data.append(swapData)
                    
                    data.append(isHolderOnSolana ? UInt8(1) : UInt8(0))
                    
                    let instruction = TransactionInstruction(
                        keys: accounts,
                        programId: programId,
                        data: Array(data)
                    )
                    
                    let preparedTransaction = try await blockchainClient.prepareTransaction(
                        instructions: [instruction],
                        signers: [keyPair],
                        feePayer: keyPair.publicKey
                    )
                    
                    let _ = try await blockchainClient.sendTransaction(
                        preparedTransaction: preparedTransaction
                    )
                    
                    self.info("settleInvoice", party)
                    fulfill(party)
                } catch {
                    self.error("settleInvoice", error)
                    reject(error)
                }
            }
        }
    }
}

extension Solana {
    private func swapArgs(event: Any, signature: String, step: Step) -> (String, SwapDiff) {
        var swap: SwapInfo
        var isHolder: Bool
        
        switch event {
        case let lockEvent as LockEvent:
            swap = lockEvent.swap
            isHolder = lockEvent.is_holder
        case let unlockEvent as UnlockEvent:
            swap = unlockEvent.swap
            isHolder = unlockEvent.is_holder
        default:
            fatalError("Invalid event type")
        }
        
        if isHolder && step == .lock {
            let swapId = String(swap.id.dropFirst(2))
            return (
                "swapHolderPaid",
                HolderPaidSwap(id: swapId, secretHolder: signature)
            )
        } else if !isHolder && step == .lock {
            let swapId = String(swap.id.dropFirst(2))
            return (
                "swapSeekerPaid",
                SeekerPaidSwap(id: swapId, secretSeeker: signature)
            )
        } else if isHolder && step == .unlock {
            let unlockEvent = event as! UnlockEvent
            let secret = Data(hex: unlockEvent.secret)
            let swapId = String(swap.id.dropFirst(2))

            return (
                "swapHolderSettled",
                HolderSettledSwap(id: swapId, secret: secret)
            )
        } else if !isHolder && step == .unlock {
            let swapId = String(swap.id.dropFirst(2))

            return (
                "swapSeekerSettled",
                SeekerSettledSwap(id: swapId)
            )
        }
        
        fatalError("Invalid swap state")
    }
    
    private func liquidityArgs(event: Any, signature: String, slot: UInt64) -> Liquidity {
        var id = "0x\(txSigTo32Bytes(signature))"
        
        switch event {
        case let withdrawEvent as WithdrawEvent:
            id = "0x\(withdrawEvent.id)"
        default:
            break
        }
        
        var tokenMint: String = ""
        var amount: UInt64 = 0
        var maker: String = ""
        var portalAddress: String = ""
        
        switch event {
        case let depositEvent as DepositEvent:
            tokenMint = depositEvent.token_mint
            amount = depositEvent.amount
            maker = depositEvent.maker
            portalAddress = depositEvent.portal_address
        case let withdrawEvent as WithdrawEvent:
            tokenMint = withdrawEvent.token_mint
            amount = withdrawEvent.amount
            maker = withdrawEvent.maker
            portalAddress = withdrawEvent.portal_address
        default:
            fatalError("Invalid event type")
        }
        
        return try! Liquidity(
            id: id,
            ts: try! BigUInt(slot),
            chain: "solana",
            symbol: "SOL",
            contractAddress: tokenMint,
            nativeAmount: BigInt(amount),
            nativeAddress: maker,
            portalAddress: portalAddress
        )
    }

    private func txSigTo32Bytes(_ signature: String) -> String {
        let data = Data(base58: signature) ?? Data()
        let bytes32 = data.prefix(32)
        
        // Pad with zeros if less than 32 bytes
        var result = bytes32
        while result.count < 32 {
            result.append(0)
        }
        
        return result.hex
    }
    
    private func txSignatureToHex(_ signature: String) -> String {
        let data = Data(signature.utf8)
        let hex = data.map { String(format: "%02x", $0) }.joined()
        
        if hex.count >= 64 {
            return String(hex.prefix(64))
        } else {
            return hex.padding(toLength: 64, withPad: "0", startingAt: 0)
        }
    }
    
    private func wrapSol(_ amount: BigInt) async throws {
        let wrappedSolATA = try getMyAssociatedTokenAddress(
            assetAddress: NATIVE_MINT.base58EncodedString,
            isSOL: true
        )
        
        let amountLamports = UInt64(truncatingIfNeeded: amount)
        
        // 1. Create ATA for wrapped SOL if it doesn't exist
        let accountInfoResult: BufferInfo<TokenAccountState>? = try await apiClient.getAccountInfo(account: wrappedSolATA.base58EncodedString)
        let accountExists = accountInfoResult != nil
        
        var instructions: [TransactionInstruction] = []
        
        // If account doesn't exist, create it
        if !accountExists {
            let createATAInstruction = try AssociatedTokenProgram.createAssociatedTokenAccountInstruction(
                mint: NATIVE_MINT,
                owner: keyPair.publicKey,
                payer: keyPair.publicKey,
                tokenProgramId: TOKEN_PROGRAM_ID
            )
            instructions.append(createATAInstruction)
        }
        
        // 2. Transfer SOL to the ATA
        let transferInstruction = SystemProgram.transferInstruction(
            from: keyPair.publicKey,
            to: wrappedSolATA,
            lamports: amountLamports
        )
        
        // 3. Create SyncNative instruction manually
        let syncNativeInstructionData: [UInt8] = [17]
        let syncNativeInstruction = TransactionInstruction(
            keys: [
                AccountMeta(publicKey: wrappedSolATA, isSigner: false, isWritable: true)
            ],
            programId: TOKEN_PROGRAM_ID,
            data: syncNativeInstructionData
        )
        
        // Combine all instructions
        instructions.append(transferInstruction)
        instructions.append(syncNativeInstruction)
        
        let preparedTransaction = try await blockchainClient.prepareTransaction(
            instructions: instructions,
            signers: [keyPair],
            feePayer: keyPair.publicKey
        )
        
        let txId = try await blockchainClient.sendTransaction(preparedTransaction: preparedTransaction)
        print("txId: \(txId)")
    }
    
    private func getFundAndVault(assetAddress: String, isSOL: Bool = false, maker: PublicKey? = nil) throws -> (fund: PublicKey, vault: PublicKey) {
        let tokenMint = try PublicKey(string: assetAddress)
        let makerAddy = maker ?? keyPair.publicKey
        
        let fundSeed = [
            "fund".data(using: .utf8)!,
            makerAddy.data,
            tokenMint.data
        ]
        
        let (fund, _) = try PublicKey.findProgramAddress(
            seeds: fundSeed,
            programId: programId
        )
        
        let vault = try PublicKey.associatedTokenAddress(
            walletAddress: fund,
            tokenMintAddress: tokenMint,
            tokenProgramId: tokenProgramId(isSOL: isSOL)
        )
        
        return (fund, vault)
    }
    
    private func getMyAssociatedTokenAddress(assetAddress: String, isSOL: Bool = false) throws -> PublicKey {
        try PublicKey.associatedTokenAddress(
            walletAddress: keyPair.publicKey,
            tokenMintAddress: try PublicKey(string: assetAddress),
            tokenProgramId: tokenProgramId(isSOL: isSOL)
        )
    }
    
    private func invoiceAddress(hash: Data) throws -> PublicKey {
        let invoiceSeeds = [
            "invoice".data(using: .utf8)!,
            keyPair.publicKey.data,
            hash
        ]
        
        let (invoiceAddress, _) = try PublicKey.findProgramAddress(
            seeds: invoiceSeeds,
            programId: programId
        )
        
        return invoiceAddress
    }
    
    private func getHtlAndPurse(hash: Data, assetAddress: String, nativeAddress: PublicKey, isSOL: Bool = false) throws -> (htl: PublicKey, purse: PublicKey) {
        let tokenMint = try PublicKey(string: assetAddress)
        
        let htlSeeds: [Data] = [
            "htl".data(using: .utf8)!,
            nativeAddress.data,
            hash
        ]
        
        let (htl, _) = try PublicKey.findProgramAddress(
            seeds: htlSeeds,
            programId: programId
        )
        
        // Get ATA for purse with allowOwnerOffCurve=true (matching TypeScript's getAta)
        let purse = try PublicKey.associatedTokenAddress(
            walletAddress: htl,
            tokenMintAddress: tokenMint,
            tokenProgramId: tokenProgramId(isSOL: isSOL)
        )
        
        return (htl, purse)
    }
    
    private func tokenProgramId(isSOL: Bool) -> PublicKey {
        isSOL ? TOKEN_PROGRAM_ID : TOKEN_2022_PROGRAM_ID
    }
}

extension Data {
    init?(base58: String) {
        // Implementation of base58 decoding
        // You'll need a proper base58 decoding implementation
        // This is a placeholder
        guard let data = base58.data(using: .utf8) else { return nil }
        self = data
    }
    
    var hex: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
