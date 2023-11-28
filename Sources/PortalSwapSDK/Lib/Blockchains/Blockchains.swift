import Combine
import Promises

class Blockchains: BaseClass {
    private let sdk: Sdk!
    private let ethereum: Ethereum!
    private let lightning: Lightning!
    
    private var subscriptions = Set<AnyCancellable>()
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains) {
        self.sdk = sdk
        
        self.ethereum = Ethereum(sdk: sdk, props: props.ethereum)
        self.lightning = Lightning(sdk: sdk, props: props.lightning)
        
        super.init(id: "Blockchains")
        
        let forwardLogEvent: ([Any]) -> Void = { [weak self] args in
            if let level = args.first as? String, let loggingFunction = self?.getLoggingFunction(for: LogLevel.level(level)) {
                loggingFunction(Array(args.dropFirst()))
            }
        }
        
        self.ethereum.on("log", forwardLogEvent).store(in: &subscriptions)
        self.lightning.on("log", forwardLogEvent).store(in: &subscriptions)
    }
    
    func connect() -> Promise<Void> {
        Promise { [unowned self] fulfill, reject in
            all(ethereum.connect(), lightning.connect())
                .then { ethereum, lightning in
                    fulfill(())
                }.catch { error in
                    reject(error)
                }
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] fulfill, reject in
            all(ethereum.disconnect(), lightning.disconnect())
                .then { ethereum, lightning in
                    fulfill(())
                }.catch { error in
                    reject(error)
                }
        }
    }
}

extension Blockchains {
    private func getLoggingFunction(for level: LogLevel) -> ([Any]) -> Void {
        switch level {
        case .debug:
            return { args in
                print("DEBUG:", args)
            }
        case .info:
            return { args in
                print("INFO:", args)
            }
        case .warn:
            return { args in
                print("WARN:", args)
            }
        case .error:
            return { args in
                print("ERROR:", args)
            }
        case .unknown:
            return { args in
                print("Unknown:", args)
            }
        }
    }
}