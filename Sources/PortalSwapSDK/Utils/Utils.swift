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
        return Data(hex: secret.toHexString())
    }
    
    static func sha256(data: Data) -> Data {
        data.sha256()
    }
    
    static func isEIP55Compliant(address: String) -> Bool {
        let trimmedAddress = address.lowercased().replacingOccurrences(of: "0x", with: "")
        let hash = trimmedAddress.data(using: .utf8)!.sha3(.keccak256).toHexString()

        for (char, hashChar) in zip(address, hash) {
            if char.isLetter {
                if (hashChar.isNumber && hashChar.wholeNumberValue! >= 8 && char.isLowercase) ||
                   (hashChar.isNumber && hashChar.wholeNumberValue! < 8 && char.isUppercase) {
                    return false
                }
            }
        }
        return true
    }
    
    static func convertToJSON<T: Codable>(_ object: T) -> [String: Any]? {
        do {
            let jsonData = try JSONEncoder().encode(object)
            if let jsonDict = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                return jsonDict
            }
        } catch {
            print("Error converting object to JSON dictionary: \(error)")
        }
        return nil
    }
    
    static func hexToData(_ string: String) -> Data? {
        var hex = string
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        var data = Data()
        while(hex.count > 0) {
            let subIndex = hex.index(hex.startIndex, offsetBy: 2)
            let c = String(hex[..<subIndex])
            hex = String(hex[subIndex...])
            var ch: UInt64 = 0
            Scanner(string: c).scanHexInt64(&ch)
            data.append(try! UInt8(ch))
        }
        return data
    }
}
