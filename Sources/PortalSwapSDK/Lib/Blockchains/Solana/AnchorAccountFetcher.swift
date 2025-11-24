import Foundation
import SolanaSwift

class AnchorAccountFetcher {
    private let apiClient: SolanaAPIClient
    
    init(apiClient: SolanaAPIClient) {
        self.apiClient = apiClient
    }
    
    // Fetch invoice account similar to Anchor's account.invoice.fetch()
    func fetchInvoice(address: PublicKey) async throws -> InvoiceAccountState {
        let maxRetries = 5
        let delaySeconds: UInt64 = 5_000_000_000
        
        for attempt in 1...maxRetries {
            do {
                let accountInfo: BufferInfo<InvoiceAccountState>? = try await apiClient.getAccountInfo(
                    account: address.base58EncodedString
                )
                
                guard let account = accountInfo else {
                    if attempt == maxRetries {
                        throw SwapSDKError.msg("Invoice account not found at address: \(address.base58EncodedString)")
                    }
                    
                    try await Task.sleep(nanoseconds: delaySeconds)
                    continue
                }
                
                return account.data
            } catch {
                if attempt == maxRetries { throw error }
                try await Task.sleep(nanoseconds: delaySeconds)
            }
        }
        

        throw SwapSDKError.msg("Max retries exceeded")
    }

    func fetchHTLC(address: PublicKey) async throws -> HTLCAccountState {
        let maxRetries = 5
        let delaySeconds: UInt64 = 5_000_000_000

        for attempt in 1...maxRetries {
            do {
                let accountInfo: BufferInfo<HTLCAccountState>? = try await apiClient.getAccountInfo(
                    account: address.base58EncodedString
                )

                guard let account = accountInfo else {
                    if attempt == maxRetries {
                        throw SwapSDKError.msg("HTLC account not found at address: \(address.base58EncodedString)")
                    }

                    try await Task.sleep(nanoseconds: delaySeconds)
                    continue
                }

                return account.data
            } catch {
                if attempt == maxRetries { throw error }
                try await Task.sleep(nanoseconds: delaySeconds)
            }
        }

        throw SwapSDKError.msg("Max retries exceeded")
    }
}

extension SolanaAPIClient {
    func fetchInvoice(at address: PublicKey) async throws -> InvoiceAccountState {
        let fetcher = AnchorAccountFetcher(apiClient: self)
        return try await fetcher.fetchInvoice(address: address)
    }

    func fetchHTLC(at address: PublicKey) async throws -> HTLCAccountState {
        let fetcher = AnchorAccountFetcher(apiClient: self)
        return try await fetcher.fetchHTLC(address: address)
    }
}
