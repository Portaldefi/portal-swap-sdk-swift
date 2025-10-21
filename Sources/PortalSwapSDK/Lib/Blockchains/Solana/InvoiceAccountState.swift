import Foundation
import SolanaSwift

public struct InvoiceAccountState: BufferLayout {
    public static let BUFFER_LENGTH: UInt64 = 146
    
    public let initialized: Bool
    public let secretHash: Data
    public let payeePubkey: PublicKey
    public let payerPubkey: PublicKey
    public let tokenMint: PublicKey
    public let amount: UInt64
    public let bump: UInt8
}

extension InvoiceAccountState: BorshCodable {
    // Anchor discriminator size
    private static let DISCRIMINATOR_SIZE = 8
    
    public func serialize(to writer: inout Data) throws {
        // For Anchor accounts, we should include the discriminator when serializing
        // But since this is just for reading, we'll focus on deserialization
        
        // Serialize initialized as u8 (0 or 1)
        let initializedByte: UInt8 = initialized ? 1 : 0
        try initializedByte.serialize(to: &writer)
        
        // Serialize secret_hash (32 bytes)
        guard secretHash.count == 32 else {
            throw BorshCodableError.invalidData
        }
        writer.append(secretHash)
        
        // Serialize pubkeys
        try payeePubkey.serialize(to: &writer)
        try payerPubkey.serialize(to: &writer)
        try tokenMint.serialize(to: &writer)
        
        // Serialize amount as u64
        try amount.serialize(to: &writer)
        
        // Serialize bump as u8
        try bump.serialize(to: &writer)
    }
    
    public init(from reader: inout BinaryReader) throws {
        // Skip the 8-byte Anchor discriminator
        _ = try reader.read(count: InvoiceAccountState.DISCRIMINATOR_SIZE)
        
        // Now read the actual data
        // Read initialized as bool from u8
        let initializedByte = try UInt8(from: &reader)
        initialized = initializedByte != 0
        
        // Read secret_hash (32 bytes)
        let hash = try reader.read(count: 32)
        secretHash = Data(hash)
        
        // Read pubkeys
        payeePubkey = try PublicKey(from: &reader)
        payerPubkey = try PublicKey(from: &reader)
        tokenMint = try PublicKey(from: &reader)
        
        // Read amount as u64
        amount = try UInt64(from: &reader)
        
        // Read bump as u8
        bump = try UInt8(from: &reader)
    }
}

extension InvoiceAccountState {
    /// Checks if the invoice is valid (initialized)
    public var isValid: Bool {
        return initialized
    }
    
    /// Returns the secret hash as a hex string for debugging
    public var secretHashHex: String {
        return secretHash.map { String(format: "%02hhx", $0) }.joined()
    }
}

extension InvoiceAccountState: Equatable {
    public static func == (lhs: InvoiceAccountState, rhs: InvoiceAccountState) -> Bool {
        return lhs.initialized == rhs.initialized &&
               lhs.secretHash == rhs.secretHash &&
               lhs.payeePubkey == rhs.payeePubkey &&
               lhs.payerPubkey == rhs.payerPubkey &&
               lhs.tokenMint == rhs.tokenMint &&
               lhs.amount == rhs.amount &&
               lhs.bump == rhs.bump
    }
}
