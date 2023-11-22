import CryptoKit
import Foundation

class Utils {
    static func keccak256Hash(of eventSignature: String) -> String {
        let hash = eventSignature.data(using: .utf8)!.sha3(.keccak256)
        return hash.toHexString()
    }
    
    static func toHex(_ value: Int64) -> String {
        "0x" + String(value, radix: 16)
    }
    
    static func createSecret() -> Data {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = randomBytes.withUnsafeMutableBufferPointer { bufferPointer in
            SecRandomCopyBytes(kSecRandomDefault, 32, bufferPointer.baseAddress!)
        }
        
        let secret = randomBytes
        let secretData = Data(hex: secret.toHexString())
        return secretData.sha256()
    }
}
