import Foundation
import Combine

open class BaseClass: CustomDebugStringConvertible {
    public typealias EventName = String
    
    let id = UUID()

    public let instanceId: String
    private var subjects = [EventName: PassthroughSubject<[Any], Never>]()
    private var listenerSubscriptions = [EventName: [UUID: AnyCancellable]]()
    private var subscriptions = Set<AnyCancellable>()
    
    private let logLevels = ["debug", "info", "warn", "error"]

    public init(id: String) {
        instanceId = id
    }
    
    // MARK: - Event Management
    
    public func emit(event: EventName, args: [Any]? = []) {
        guard let subject = subjects[event] else { return }
        subject.send(args ?? [])
    }
    
    @discardableResult
    public func on(_ event: EventName, _ action: @escaping ([Any]) -> Void) -> Self {
        if subjects[event] == nil {
            subjects[event] = PassthroughSubject<[Any], Never>()
        }

        let cancellable = subjects[event]!.sink(receiveValue: action)
        listenerSubscriptions[event, default: [:]][id] = cancellable
        
        // Automatically store the subscription internally
        subscribe(cancellable)

        emit(event: "newListener", args: [event, id])
        return self
    }
    
    public func once(_ event: EventName, _ action: @escaping ([Any]) -> Void) {
        if subjects[event] == nil {
            subjects[event] = PassthroughSubject<[Any], Never>()
        }

        let id = UUID()
        var cancellable: AnyCancellable?
        cancellable = subjects[event]!.sink { [weak self] args in
            action(args)
            self?.removeListener(event: event, listenerId: id)
        }

        listenerSubscriptions[event, default: [:]][id] = cancellable
        subscribe(cancellable!)
        emit(event: "newListener", args: [event, id])
    }
    
    public func off(_ event: EventName) {
        removeListener(event: event, listenerId: id)
    }
    
    public func removeAllListeners(event: EventName? = nil) {
        if let event = event {
            removeListeners(for: event)
        } else {
            for eventName in subjects.keys {
                removeListeners(for: eventName)
            }
        }
    }
    
    private func removeListener(event: EventName, listenerId: UUID) {
        guard let cancellable = listenerSubscriptions[event]?[listenerId] else { return }
        cancellable.cancel()
        listenerSubscriptions[event]?.removeValue(forKey: listenerId)
        emit(event: "removeListener", args: [event, listenerId])
    }
    
    private func removeListeners(for event: EventName) {
        listenerSubscriptions[event]?.values.forEach { $0.cancel() }
        listenerSubscriptions[event]?.keys.forEach { emit(event: "removeListener", args: [event, $0]) }
        listenerSubscriptions.removeValue(forKey: event)
        subjects.removeValue(forKey: event)
    }
    
    public func eventNames() -> [EventName] {
        Array(subjects.keys)
    }
    
    public func listeners(for event: EventName) -> [UUID] {
        guard let subscriptions = listenerSubscriptions[event] else { return [] }
        return Array(subscriptions.keys)
    }

    // MARK: - Logging
    
    func debug(_ event: String, _ args: Any...) {
        logFunction("debug", event, args)
    }

    func info(_ event: String, _ args: Any...) {
        logFunction("info", event, args)
    }

    func warn(_ event: String, _ args: Any...) {
        logFunction("warn", event, args)
    }

    func error(_ event: String, _ args: Any...) {
        logFunction("error", event, args)
        emit(event: "error", args: [event, args])
    }
    
    private func logFunction(_ level: String, _ event: String, _ args: [Any]) {
        emit(event: "log", args: [level, "(\(instanceId)) \(event)"] + args)
    }

    // MARK: - Serialization
    
    public func toJSON() -> [String: Any] {
        ["id": instanceId]
    }
    
    public var debugDescription: String {
        "\(Self.self)(\(toJSON()))"
    }
    
    // MARK: - Helper Functions
    
    private func subscribe(_ subscription: AnyCancellable) {
        subscription.store(in: &subscriptions)
    }

    private enum LogLevel: String {
        case debug, info, warn, error, unknown
        
        static func level(_ level: String) -> LogLevel {
            LogLevel(rawValue: level.lowercased()) ?? .unknown
        }
    }
}
