import Foundation

struct OrderData: Codable {
    let id: UUID
    let uid: String
    let side: String
    let baseAsset: String
    let baseNetwork: String
    let baseQuantity: Int32
    let quoteAsset: String
    let quoteNetwork: String
    let quoteQuantity: Int64
}
