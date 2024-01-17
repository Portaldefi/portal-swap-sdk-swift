public struct PartyModel {
    public let id: String
    public let oid: String
    public let asset: String
    public let blockchain: String
    public let quantity: Int64
    
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
    }
}
