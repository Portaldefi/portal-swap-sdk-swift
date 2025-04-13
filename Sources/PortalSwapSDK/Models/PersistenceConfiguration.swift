struct PersistenceConfiguration {
    public init(
        accountId: String,
        modelName: String,
        cloudIdentifier: String,
        configuration: String
    ) {
        self.accountId = accountId
        self.modelName = modelName
        self.cloudIdentifier = cloudIdentifier
        self.configuration = configuration
    }
    
    public let accountId: String
    public let modelName: String
    public let cloudIdentifier: String
    public let configuration: String
}
