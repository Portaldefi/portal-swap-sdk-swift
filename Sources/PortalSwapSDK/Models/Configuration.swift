import Promises
import SolanaSwift

public struct SwapSdkConfig {
    public struct Blockchains {
        public struct Portal {
            public let rpcUrl: String
            public let chainId: String
            public let privKey: String
            public let userAddress: String
            
            public let liquidityManagerContractAddress: String
            public let assetManagerContractAddress: String
            public let swapManagerContractAddress: String
            public let orderbookMarketContractAddress: String
            
            public init(rpcUrl: String, chainId: String, privKey: String, userAddress: String, liquidityManagerContractAddress: String, assetManagerContractAddress: String, swapManagerContractAddress: String, orderbookMarketContractAddress: String) {
                self.rpcUrl = rpcUrl
                self.chainId = chainId
                self.privKey = privKey
                self.userAddress = userAddress
                
                self.liquidityManagerContractAddress = liquidityManagerContractAddress
                self.assetManagerContractAddress = assetManagerContractAddress
                self.swapManagerContractAddress = swapManagerContractAddress
                self.orderbookMarketContractAddress = orderbookMarketContractAddress
            }
        }
        
        public struct Ethereum {
            public let url: String
            public let chainId: String
            public let contracts: [String: Any]
            public let privKey: String
            public let traderAddress: String
            public let nativeLiquidityManagerContractAddress: String
            public let invoiceManagerContractAddress: String
            
            public init(url: String, chainId: String, contracts: [String: Any], privKey: String, traderAddress: String, nativeLiquidityManagerContractAddress: String, invoiceManagerContractAddress: String) {
                self.url = url
                self.chainId = chainId
                self.contracts = contracts
                self.privKey = privKey
                self.traderAddress = traderAddress
                self.nativeLiquidityManagerContractAddress = nativeLiquidityManagerContractAddress
                self.invoiceManagerContractAddress = invoiceManagerContractAddress
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
        
        public struct Solana {
            public let keyPair: KeyPair
            public let rpcUrl: String
            public let programId: String
            public let provider: BlockchainClient?
            
            public init(keyPair: KeyPair, rpcUrl: String, programId: String, provider: BlockchainClient? = nil) {
                self.keyPair = keyPair
                self.rpcUrl = rpcUrl
                self.programId = programId
                self.provider = provider
            }
        }
        
        public let ethereum: Ethereum
        public let lightning: Lightning
        public let portal: Portal
        public let solana: Solana
        
        public init(ethereum: Ethereum, lightning: Lightning, solana: Solana, portal: Portal) {
            self.ethereum = ethereum
            self.lightning = lightning
            self.solana = solana
            self.portal = portal
        }
    }
    
    public let id: String
    public let blockchains: Blockchains
    public let sellAsset: String
    public let buyAsset: String
    
    public init(id: String, sellAsset: String, buyAsset: String, blockchains: Blockchains) {
        self.id = id
        self.sellAsset = sellAsset
        self.buyAsset = buyAsset
        self.blockchains = blockchains
    }
}
