import Web3
import Web3ContractABI

extension SolidityEvent {
    public var signature: String {
        "\(name)(\(inputs.map { $0.type.stringValue }.joined(separator: ",")))"
    }
    
    public var topic: EthereumData {
        // 1) UTF‑8 bytes of the signature string
        let utf8Bytes = Array(signature.utf8)
        // 2) Keccak‑256 hash those bytes
        let hashBytes = utf8Bytes.sha3(.keccak256)
        // 3) Wrap into EthereumData
        return EthereumData(hashBytes)
    }
}
