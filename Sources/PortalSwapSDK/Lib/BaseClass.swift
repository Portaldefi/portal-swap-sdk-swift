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
        
        onceCancellable = subjects[event]!.sink(receiveValue: { [weak self] args in
            action(args)
            onceCancellable?.cancel()
            
            if let cancellable = onceCancellable {
                self?.subscriptions.remove(cancellable)
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
        emit(event: "error", args: [event, args])
    }
    
    func forwardSwap() -> ([Any]) -> Void {
        { [weak self] args in
            if let data = args as? [AmmSwap], let swap = data.first {
                self?.emit(event: "swap.\(swap.status)", args: [swap])
            } else {
                self?.debug("Unexpected arguments on forwardSwap: \(args) [Sdk]")
            }
        }
    }
    
    func forwardEvent(_ event: String) -> ([Any]) -> Void {
        { [weak self] args in
            self?.emit(event: event, args: args)
        }
    }
    
    func forwardLog() -> ([Any]) -> Void {
        { [weak self] args in
            if let level = args.first as? String
            {
                let argsArray = Array(args.dropFirst())
                if let loggingFunction = self?.getLoggingFunction(for: LogLevel.level(level)) {
                    loggingFunction(argsArray)
                    
                    switch LogLevel.level(level) {
                    case .debug:
                        self?.emit(event: "debug", args: [argsArray])
                    case .info:
                        self?.emit(event: "info", args: [argsArray])
                    case .warn:
                        self?.emit(event: "warn", args: [argsArray])
                    case .error:
                        self?.emit(event: "error", args: [argsArray])
                    case .unknown:
                        break
                    }
                }
            } else {
                self?.emit(event: "log", args: args)
            }
        }
    }
    
    func forwardError() -> ([Any]) -> Void {
        { [weak self] args in
            self?.emit(event: "error", args: args)
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
                print("[\(Date())] SWAP SDK DEBUG: \(args.first ?? String())")
            case .info:
                print("[\(Date())] SWAP SDK INFO: \(args.first ?? String())")
            case .warn:
                print("[\(Date())] SWAP SDK WARN: \(args.first ?? String())")
            case .error:
                print("[\(Date())] SWAP SDK ERROR: \(args.first ?? String())")
            case .unknown:
                print("[\(Date())] SWAP SDK unknown message level: \(args.first ?? String())")
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
