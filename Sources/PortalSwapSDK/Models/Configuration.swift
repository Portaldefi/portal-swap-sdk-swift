import Promises

public struct SwapSdkConfig {
    public struct Network {
        public enum NetworkProtocol {
            case unencrypted
            case encrypted
        }
        public let networkProtocol: NetworkProtocol
        public let hostname: String
        public let port: Int
        
        public init(networkProtocol: NetworkProtocol, hostname: String, port: Int) {
            self.networkProtocol = networkProtocol
            self.hostname = hostname
            self.port = port
        }
    }
    
    public struct Blockchains {
        public struct Ethereum {
            public let url: String
            public let chainId: String
            public let contracts: [String: Any]
            public let privKey: String
            
            public init(url: String, chainId: String, contracts: [String: Any], privKey: String) {
                self.url = url
                self.chainId = chainId
                self.contracts = contracts
                self.privKey = privKey
            }
        }
        
        public struct Lightning {
            public let client: ILightningClient
            
            public init(client: ILightningClient) {
                self.client = client
            }
        }
        
        public let ethereum: Ethereum
        public let lightning: Lightning
        
        public init(ethereum: Ethereum, lightning: Lightning) {
            self.ethereum = ethereum
            self.lightning = lightning
        }
    }
    
    public let id: String
    public let network: Network
    public let blockchains: Blockchains
    
    public init(id: String, network: Network, blockchains: Blockchains) {
        self.id = id
        self.network = network
        self.blockchains = blockchains
    }
}
