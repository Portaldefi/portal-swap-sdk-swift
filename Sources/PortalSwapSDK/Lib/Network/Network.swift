import Foundation
import WebSocketKit
import NIO
import Promises

final class Network: BaseClass {
    private let config: NetworkConfig
    private let sdk: Sdk
    private var socket: WebSocket?
    private let socketEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
    var isConnected: Bool {
        guard let ws = socket else { return false }
        return !ws.isClosed
    }
    
    init(sdk: Sdk, props: SwapSdkConfig.Network) {
        config = NetworkConfig(
            networkProtocol: props.networkProtocol,
            hostName: props.hostname,
            port: props.port,
            pathname: "api/v1/updates"
        )
        
        self.sdk = sdk
        
        super.init(id: "Network")
    }
        
    func connect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            WebSocket.connect(
                to: webSocketURL(userId: sdk.userId),
                on: socketEventLoopGroup
            ) { [weak self] ws in
                
                guard let self = self else {
                    return reject(SwapSDKError.msg("Websocket self is nil"))
                }

                self.socket = ws
                
                ws.onText { ws, text in
                    self._onMessage(text)
                }
            }
            .whenComplete { [weak self] result in
                switch result {
                case .failure(let error):
                    reject(SwapSDKError.msg("WebSocket connection failed with error: \(error)"))
                case .success:
                    self?.debug("\(self?.sdk.userId ?? "unknown user") webSocket connected")
                    resolve(())
                }
            }
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            guard let ws = socket else {
                return reject(SwapSDKError.msg("Network: Socket is nil on disconnect"))
            }
            ws.close().whenComplete { _ in
                self.socket = nil
                resolve(())
            }
        }
    }
    
    func request(args: [String: String], data: [String: Any]) -> Promise<Data> {
        Promise { [unowned self] resolve, reject in
            guard let path = args["path"] else {
                return reject(SwapSDKError.msg("Invalid Path"))
            }
            
            guard let url = URL(string: serverURL(path: path)) else {
                return reject(SwapSDKError.msg("Invalid URL"))
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = args["method"] ?? "GET"
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                
                let creds = "\(sdk.userId):\(sdk.userId)"
                let base64Creds = Data(creds.utf8).base64EncodedString()
                
                request.addValue("application/json", forHTTPHeaderField: "Accept")
                request.addValue("application/json", forHTTPHeaderField: "Accept-Encoding")
                request.addValue("Basic \(base64Creds)", forHTTPHeaderField: "Authorization")
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.addValue("identity", forHTTPHeaderField: "Content-Encoding")
                request.addValue("\(jsonData.count)", forHTTPHeaderField: "Content-Length")
                
                request.httpBody = jsonData
            } catch {
                reject(SwapSDKError.msg("JSON serialization error"))
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    reject(error)
                } else if let data = data {
                    resolve(data)
                } else {
                    reject(SwapSDKError.msg("No data received"))
                }
            }
            .resume()
        }
    }
    
    func send(args: [String: Any]) -> Promise<Void> {
        Promise { [unowned self] resolve, reject in
            do {
                let dataDict = try JSONSerialization.data(withJSONObject: args, options: .prettyPrinted)
                guard let ws = socket else {
                    return reject(SwapSDKError.msg("Network: failed to send message over socket. Socket is nil"))
                }
                ws.send(dataDict.bytes)
                resolve(())
            } catch {
                reject(SwapSDKError.msg("Network: JSON serialization error: \(error)"))
            }
        }
    }
    
    func _onMessage(_ message: String) {
        var event: String
        var arg: Any
        
        do {
            if let data = message.data(using: .utf8),
               let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                
                if let type = jsonObject["@type"] as? String,
                   let status = jsonObject["status"] {
                    event = "\(type.lowercased()).\(status)"
                    arg = [jsonObject]
                    
                    debug("Forwarding socket event type: \(type), status: \(status), obj: \(jsonObject)")
                } else if let eventValue = jsonObject["@event"] as? String,
                          let dataValue = jsonObject["@data"] {
                    event = eventValue
                    arg = dataValue
                } else {
                    event = "message"
                    arg = [jsonObject]
                }
                
            } else {
                event = "message"
                arg = [message]
            }
        } catch {
            event = "error"
                arg = error
        }
        
        emit(event: event, args: [arg])
    }
}

extension Network {
    struct NetworkConfig {
        let networkProtocol: SwapSdkConfig.Network.NetworkProtocol
        let hostName: String
        let port: Int
        let pathname: String
    }
    
    private func serverURL(path: String) -> String {
        switch config.networkProtocol {
        case .unencrypted:
            return "http://\(config.hostName):\(config.port)\(path)"
        case .encrypted:
            return "https://\(config.hostName)\(path)"
        }
    }
    
    private func webSocketURL(userId: String) -> String {
        switch config.networkProtocol {
        case .unencrypted:
            //Playnet
            return "ws://\(config.hostName):\(config.port)/\(config.pathname)/\(userId)"
        case .encrypted:
            return "wss://\(config.hostName)/\(config.pathname)/\(userId)"
        }
    }
}
