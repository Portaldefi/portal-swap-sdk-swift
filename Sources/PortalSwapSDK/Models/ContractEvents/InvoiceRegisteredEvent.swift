import Foundation
import Web3

struct InvoiceRegisteredEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case address, topics, data, blockNumber, transactionHash, transactionIndex, blockHash, logIndex, removed
    }

    let swapId: String
    let secretHash: String
    let amount: BigUInt
    let invoice: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataString = try container.decode(String.self, forKey: .data)
        
        let dataSubstring = dataString.dropFirst(2) // Remove "0x" prefix

        func decodeBytes32(from hexString: String) -> String {
            return "0x" + hexString
        }

        func decodeBigUInt(from hexString: String) -> BigUInt {
            return BigUInt(hexString, radix: 16) ?? BigUInt(0)
        }

        // Extract and decode each parameter
        let idHex = String(dataSubstring.prefix(64))
        swapId = decodeBytes32(from: idHex)

        let remainingData1 = dataSubstring.dropFirst(64)
        let secretHashHex = String(remainingData1.prefix(64))
        secretHash = decodeBytes32(from: secretHashHex)

        let remainingData2 = remainingData1.dropFirst(64)
        let amountHex = String(remainingData2.prefix(64))
        amount = decodeBigUInt(from: amountHex)

        let remainingData3 = remainingData2.dropFirst(64)
        let invoiceHex = String(remainingData3.prefix(64))
        invoice = invoiceHex 
    }
    
    init(swapId: String, secretHash: String, amount: BigUInt, invoice: String) {
        self.swapId = swapId
        self.secretHash = secretHash
        self.amount = amount
        self.invoice = invoice
    }
    
    public func encode(to encoder: Encoder) throws {}
}
