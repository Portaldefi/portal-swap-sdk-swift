import Foundation
import Combine

open class BaseClass {
    public typealias EventName = String
    
    private var subscriptions = Set<AnyCancellable>()
    public func subscribe(_ subscription: AnyCancellable) {
        subscription.store(in: &subscriptions)
    }
    
    private var instances: [ObjectIdentifier: InstanceData] = [:]
    private let logLevels = ["debug", "info", "warn", "error"]
    
    struct InstanceData {
        let id: String?
        var subjects: [EventName: PassthroughSubject<[Any], Never>]
        var cancellables: Set<AnyCancellable>
    }
    
    public var id: String? {
        instances[ObjectIdentifier(self)]?.id
    }
    
    public init(id: String? = nil) {
        instances[ObjectIdentifier(self)] = InstanceData(id: id != nil ? id : nil, subjects: [:], cancellables: [])
    }
    
    private func logFunction(_ level: String, _ event: String, _ args: [Any]) {
        if let id = self.id {
            emit(event: "log", args: [level, "\(id).\(event)"] + args)
        } else {
            emit(event: "log", args: [level, event] + args)
        }
    }
    
    public func emit(event: EventName, args: [Any]? = []) {
        instances[ObjectIdentifier(self)]?.subjects[event]?.send(args ?? [])
    }
    
    @discardableResult
    public func on(_ event: EventName, _ action: @escaping ([Any]) -> Void) -> AnyCancellable {
        if instances[ObjectIdentifier(self)]?.subjects[event] == nil {
            instances[ObjectIdentifier(self)]?.subjects[event] = PassthroughSubject<[Any], Never>()
        }

        var cancellablesSet = instances[ObjectIdentifier(self)]?.cancellables ?? Set<AnyCancellable>()
        let cancellable = instances[ObjectIdentifier(self)]!.subjects[event]!.sink(receiveValue: action)
        cancellablesSet.insert(cancellable)
        instances[ObjectIdentifier(self)]?.cancellables = cancellablesSet

        return cancellable
    }
    
    public func once(_ event: EventName, _ action: @escaping ([Any]) -> Void) {
        if instances[ObjectIdentifier(self)]?.subjects[event] == nil {
            instances[ObjectIdentifier(self)]?.subjects[event] = PassthroughSubject<[Any], Never>()
        }

        var cancellablesSet = instances[ObjectIdentifier(self)]?.cancellables ?? Set<AnyCancellable>()
        
        var onceCancellable: AnyCancellable? = nil
        onceCancellable = instances[ObjectIdentifier(self)]!.subjects[event]!.sink(receiveValue: { args in
            action(args)
            onceCancellable?.cancel()
            if let c = onceCancellable {
                cancellablesSet.remove(c)
            }
        })

        if let c = onceCancellable {
            cancellablesSet.insert(c)
            instances[ObjectIdentifier(self)]?.cancellables = cancellablesSet
        }
    }
    
    func addListener(event: EventName, action: @escaping ([Any]) -> Void) -> AnyCancellable {
        on(event, action)
    }
    
    func removeListener(event: EventName, action: AnyCancellable) {
        action.cancel()
        instances[ObjectIdentifier(self)]?.cancellables.remove(action)
    }
    
    func eventNames() -> [EventName] {
        if let subjects = instances[ObjectIdentifier(self)]?.subjects {
            return Array(subjects.keys)
        }
        return []
    }
    
    func listeners(for event: EventName) -> [AnyCancellable] {
        let cancellablesForSelf = instances[ObjectIdentifier(self)]?.cancellables ?? []
        let subject = instances[ObjectIdentifier(self)]?.subjects[event]
        let matchedCancellables = cancellablesForSelf.filter { cancellable in
            return cancellable === subject
        }
        return Array(matchedCancellables)
    }
    
    deinit {
        instances.removeValue(forKey: ObjectIdentifier(self))
    }
}

extension BaseClass {
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
    }
    
    func forwardSwap() -> ([Any]) -> Void {
        { [unowned self] args in
            if let data = args as? [Swap], let swap = data.first {
                emit(event: "swap.\(swap.status)", args: [swap])
            } else {
                debug("Got onSwap with unexpected arguments: \(args) [Sdk]")
            }
        }
    }
    
    func forwardEvent(_ event: String) -> ([Any]) -> Void {
        { [unowned self] args in
            emit(event: event, args: args)
        }
    }
    
    func forwardLog() -> ([Any]) -> Void {
        { [unowned self] args in
            if let level = args.first as? String
            {
                let loggingFunction = getLoggingFunction(for: LogLevel.level(level))
                loggingFunction(Array(args.dropFirst()))
            } else {
                emit(event: "log", args: args)
            }
        }
    }
    
    func forwardError() -> ([Any]) -> Void {
        { [unowned self] args in
            emit(event: "error", args: args)
        }
    }
    
    func getLoggingFunction(for level: LogLevel) -> ([Any]) -> Void {
        switch level {
        case .debug:
            return { args in
                print("SWAP SDK DEBUG:", args)
            }
        case .info:
            return { args in
                print("SWAP SDK INFO:", args)
            }
        case .warn:
            return { args in
                print("SWAP SDK WARN:", args)
            }
        case .error:
            return { args in
                print("SWAP SDK ERROR:", args)
            }
        case .unknown:
            return { args in
                print("SWAP SDK Unknown:", args)
            }
        }
    }
}
