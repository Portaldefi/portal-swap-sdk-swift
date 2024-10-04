import Web3
import Web3ContractABI

extension SolidityEvent {
    func topics() -> [[EthereumData]]? {
        guard let topic = try? EthereumData(ethereumValue: signature.sha3(.keccak256)) else {
            return nil
        }
        
        return [[topic]]
    }
}
