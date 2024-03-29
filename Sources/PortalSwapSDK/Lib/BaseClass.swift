import Foundation
import Combine

open class BaseClass {
    public typealias EventName = String
    
    private let instanceId: String
    private var subjects = [EventName: PassthroughSubject<[Any], Never>]()
    
    private var subscriptions = Set<AnyCancellable>()
    public func subscribe(_ subscription: AnyCancellable) {
        subscription.store(in: &subscriptions)
    }

    private let logLevels = ["debug", "info", "warn", "error"]
    
    public init(id: String) {
        instanceId = id
    }
    
    func emit(event: EventName, args: [Any]? = []) {
        subjects[event]?.send(args ?? [])
    }
    
    func on(_ event: EventName, _ action: @escaping ([Any]) -> Void) -> AnyCancellable {
        if subjects[event] == nil {
            subjects[event] = PassthroughSubject<[Any], Never>()
        }

        let cancellable = subjects[event]!.sink(receiveValue: action)
        subscribe(cancellable)

        return cancellable
    }
    
    func once(_ event: EventName, _ action: @escaping ([Any]) -> Void) {
        if subjects[event] == nil {
            subjects[event] = PassthroughSubject<[Any], Never>()
        }

        var onceCancellable: AnyCancellable? = nil
        
        onceCancellable = subjects[event]!.sink(receiveValue: { args in
            action(args)
            onceCancellable?.cancel()
            
            if let cancellable = onceCancellable {
                self.subscriptions.remove(cancellable)
            }
        })
        
        if let cancellable = onceCancellable {
            subscribe(cancellable)
        }
    }
    
    public func addListener(event: EventName, action: @escaping ([Any]) -> Void) {
        subscribe(on(event, action))
    }
    
    public func removeListener(event: EventName) {
        let subject = subjects[event]
        
        if let cancellable = subscriptions.first(where: { $0 === subject }) {
            cancellable.cancel()
            subscriptions.remove(cancellable)
        }
    }
    
    public func eventNames() -> [EventName] {
        Array(subjects.keys)
    }
    
    func listeners(for event: EventName) -> [AnyCancellable] {
        let subject = subjects[event]
        let matchedCancellables = subscriptions.filter { $0 === subject }
        return Array(matchedCancellables)
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
                debug("Unexpected arguments on forwardSwap: \(args) [Sdk]")
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
    
    private func logFunction(_ level: String, _ event: String, _ args: [Any]) {
        emit(event: "log", args: [level, "(\(instanceId)) \(event)" ] + args)
    }
    
    private func getLoggingFunction(for level: LogLevel) -> ([Any]) -> Void {
        print(String())

        return { args in
            switch level {
            case .debug:
                print("SWAP SDK DEBUG: \(args.first ?? String())")
            case .info:
                print("SWAP SDK INFO: \(args.first ?? String())")
            case .warn:
                print("SWAP SDK WARN: \(args.first ?? String())")
            case .error:
                print("SWAP SDK ERROR: \(args.first ?? String())")
            case .unknown:
                print("SWAP SDK unknown message level: \(args.first ?? String())")
            }
            
            for arg in args.dropFirst() {
                print("\(arg)")
            }
            
            if !args.dropFirst().isEmpty {
                print(String())
            }
        }
    }
}
