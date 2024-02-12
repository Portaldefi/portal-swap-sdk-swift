public struct PartyModel {
    public let id: String
    public let oid: String
    public let asset: String
    public let blockchain: String
    public let quantity: Int64
    public let invoice: InvoiceModel?
    
    init(record: DBParty) throws {
        guard let partyId = record.partyID else {
            throw SwapSDKError.msg("db swap record is missing swapId")
        }
        
        guard let partyOid = record.oid else {
            throw SwapSDKError.msg("db swap record is missing status")
        }
        
        guard let partyAsset = record.asset else {
            throw SwapSDKError.msg("db swap record is missing partyType")
        }
        
        guard let partyBlockchain = record.blockchain else {
            throw SwapSDKError.msg("db swap record is missing secret seeker")
        }
        
        id = partyId
        oid = partyOid
        
        asset = partyAsset
        blockchain = partyBlockchain
        quantity = record.quantity
        
        guard let invoiceRecord = record.invoice else {
            invoice = nil
            return
        }
        
        var lnInvoiceModel: LnInvoiceModel? = nil
        var evmInvoiceModel: EvmInvoiceModel? = nil
        
        if let lnInvoice = invoiceRecord.lightningInvoice {
            lnInvoiceModel = LnInvoiceModel(
                id: lnInvoice.invoiceID,
                request: lnInvoice.request,
                swap: lnInvoice.swap
            )
        } else if let evmInvoice = invoiceRecord.evmInvoice {
            evmInvoiceModel = EvmInvoiceModel(
                blockHash: evmInvoice.blockHash,
                from: evmInvoice.from,
                to: evmInvoice.to,
                transactionHash: evmInvoice.transactionHash
            )
        }
        
        invoice = InvoiceModel(lnInvoice: lnInvoiceModel, evmIvoice: evmInvoiceModel)
    }
}
