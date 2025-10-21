import Foundation

extension DispatchQueue {
    static let sdk: DispatchQueue = .global(qos: .userInitiated)
}
