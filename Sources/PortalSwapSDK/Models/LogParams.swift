import Web3

struct LogsParam: Codable {
    var eventName = "logs"
    
    let params: Params?
    
    struct Params: Codable {
        enum CodingKeys: String, CodingKey {
            case address = "address"
            case topics = "topics"
        }
        
        let address: [EthereumAddress]?
        let topics: [[EthereumData]]?
    }
    
    func encode(to encoder: Encoder) throws {
        if let params = params {
            var container = encoder.container(keyedBy: LogsParam.Params.CodingKeys.self)
            
            try container.encodeIfPresent(params.address, forKey: LogsParam.Params.CodingKeys.address)
            try container.encodeIfPresent(params.topics, forKey: LogsParam.Params.CodingKeys.topics)
        } else {
            var container = encoder.singleValueContainer()
            try container.encode(eventName)
        }
    }
}
