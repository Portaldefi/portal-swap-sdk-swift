public struct PersistenceConfiguration {
    
    public init(
        modelName: String,
        cloudIdentifier: String,
        configuration: String
    ) {

        self.modelName = modelName
        self.cloudIdentifier = cloudIdentifier
        self.configuration = configuration
    }
    
    public let modelName: String
    public let cloudIdentifier: String
    public let configuration: String
}
