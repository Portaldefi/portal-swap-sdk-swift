import Foundation
import SolanaSwift

public struct HTLCAccountState: BufferLayout {
    public static let BUFFER_LENGTH: UInt64 = 169

    public let secretHash: Data
    public let maker: PublicKey
    public let tokenMint: PublicKey
    public let amount: UInt64
    public let takerTokenAccount: PublicKey
    public let timeout: UInt64
    public let bump: UInt8
}

extension HTLCAccountState: BorshCodable {
    private static let DISCRIMINATOR_SIZE = 8

    public func serialize(to writer: inout Data) throws {
        guard secretHash.count == 32 else {
            throw BorshCodableError.invalidData
        }
        writer.append(secretHash)

        try maker.serialize(to: &writer)
        try tokenMint.serialize(to: &writer)
        try amount.serialize(to: &writer)
        try takerTokenAccount.serialize(to: &writer)
        try timeout.serialize(to: &writer)
        try bump.serialize(to: &writer)
    }

    public init(from reader: inout BinaryReader) throws {
        _ = try reader.read(count: HTLCAccountState.DISCRIMINATOR_SIZE)

        let hash = try reader.read(count: 32)
        secretHash = Data(hash)

        maker = try PublicKey(from: &reader)
        tokenMint = try PublicKey(from: &reader)
        amount = try UInt64(from: &reader)
        takerTokenAccount = try PublicKey(from: &reader)
        timeout = try UInt64(from: &reader)
        bump = try UInt8(from: &reader)
    }
}

extension HTLCAccountState: Equatable {
    public static func == (lhs: HTLCAccountState, rhs: HTLCAccountState) -> Bool {
        return lhs.secretHash == rhs.secretHash &&
               lhs.maker == rhs.maker &&
               lhs.tokenMint == rhs.tokenMint &&
               lhs.amount == rhs.amount &&
               lhs.takerTokenAccount == rhs.takerTokenAccount &&
               lhs.timeout == rhs.timeout &&
               lhs.bump == rhs.bump
    }
}
