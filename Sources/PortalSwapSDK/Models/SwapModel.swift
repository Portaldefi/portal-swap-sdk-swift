public struct SwapModel {
    public let swapId: String
    public let secretHolder: PartyModel
    public let secretSeeker: PartyModel
    public let status: String
    public let timestamp: Int
    public let secretHash: String?
    public let partyType: PartyType
    
    init(record: DBSwap) throws {
        guard let id = record.swapID else {
            throw SwapSDKError.msg("db swap record is missing swapId")
        }
        
        guard let swapStatus = record.status else {
            throw SwapSDKError.msg("db swap record is missing status")
        }
        
        guard let type = record.partyType else {
            throw SwapSDKError.msg("db swap record is missing partyType")
        }
        
        guard let seeker = record.secretSeeker else {
            throw SwapSDKError.msg("db swap record is missing secret seeker")
        }
        
        guard let holder = record.secretHolder else {
            throw SwapSDKError.msg("db swap record is missing secret holder")
        }
        
        swapId = id
        status = swapStatus
        
        timestamp = Int(record.timestamp)
        secretHash = record.secretHash
        
        partyType = type == "holder" ? .secretHolder : .secretSeeker
        
        let seekerModel = try PartyModel(record: seeker)
        secretSeeker = seekerModel
        
        let holderModel = try PartyModel(record: holder)
        secretHolder = holderModel
    }
}
