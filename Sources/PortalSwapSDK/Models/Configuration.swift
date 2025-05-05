import Promises

public struct SwapSdkConfig {
    public struct Blockchains {
        public struct Portal {
            public let url: String
            public let chainId: String
            public let contracts: [String: Any]
            public let privKey: String
            public let address: String
            
            public init(url: String, chainId: String, contracts: [String: Any], privKey: String, address: String) {
                self.url = url
                self.chainId = chainId
                self.contracts = contracts
                self.privKey = privKey
                self.address = address
            }
        }
        
        public struct Ethereum {
            public let url: String
            public let chainId: String
            public let contracts: [String: Any]
            public let privKey: String
            public let address: String
            
            public init(url: String, chainId: String, contracts: [String: Any], privKey: String, address: String) {
                self.url = url
                self.chainId = chainId
                self.contracts = contracts
                self.privKey = privKey
                self.address = address
            }
        }
        
        public struct Lightning {
            public let client: ILightningClient
            public let hubId: String
            
            public init(client: ILightningClient, hubId: String) {
                self.client = client
                self.hubId = hubId
            }
        }
        
        public let ethereum: Ethereum
        public let lightning: Lightning
        public let portal: Portal
        
        public init(ethereum: Ethereum, lightning: Lightning, portal: Portal) {
            self.ethereum = ethereum
            self.lightning = lightning
            self.portal = portal
        }
    }
    
    public let id: String
    public let blockchains: Blockchains
    
    public init(id: String, blockchains: Blockchains) {
        self.id = id
        self.blockchains = blockchains
    }
}
