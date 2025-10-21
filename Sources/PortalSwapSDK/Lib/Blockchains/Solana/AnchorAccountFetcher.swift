import Foundation
import SolanaSwift

class AnchorAccountFetcher {
    private let apiClient: SolanaAPIClient
    
    init(apiClient: SolanaAPIClient) {
        self.apiClient = apiClient
    }
    
    // Fetch invoice account similar to Anchor's account.invoice.fetch()
    func fetchInvoice(address: PublicKey) async throws -> InvoiceAccountState {
        // Get account info with the specific type
        let accountInfo: BufferInfo<InvoiceAccountState>? = try await apiClient.getAccountInfo(
            account: address.base58EncodedString
        )
        
        guard let account = accountInfo else {
            throw SwapSDKError.msg("Invoice account not found at address: \(address.base58EncodedString)")
        }
        
        return account.data
    }
}

extension SolanaAPIClient {
    func fetchInvoice(at address: PublicKey) async throws -> InvoiceAccountState {
        let fetcher = AnchorAccountFetcher(apiClient: self)
        return try await fetcher.fetchInvoice(address: address)
    }
}
