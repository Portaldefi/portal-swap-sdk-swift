import Foundation
import WebSocketKit
import NIO
import Promises

public class Network: BaseClass {
    struct NetworkConfig {
        let hostName: String
        let port: Int
        let pathname: String
    }
    
    private let config: NetworkConfig
    private let sdk: Sdk
    private var socket: WebSocket?
    private let socketEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
    public var isConnected: Bool {
        guard let ws = socket else { return false }
        return !ws.isClosed
    }
    
    init(sdk: Sdk, props: SwapSdkConfig.Network) {
        self.config = NetworkConfig(
            hostName: props.hostname,
            port: props.port,
            pathname: "api/v1/updates"
        )
        
        self.sdk = sdk
        
        super.init()
    }
        
    func connect() -> Promise<Void> {
        Promise { [unowned self] fulfill, reject in
            guard let id = sdk.id else {
                reject(SwapSDKError.msg("Network: missing sdk id"))
                return
            }
            
            let host = config.hostName
            let port = config.port
            let pathname = config.pathname
                                    
            WebSocket.connect(
                to: "ws://\(host):\(port)/\(pathname)/\(id)",
                on: socketEventLoopGroup
            ) { [weak self] ws in
                
                guard let self = self else {
                    return reject(SwapSDKError.msg("Websocket self is nil"))
                }

                self.socket = ws
                
                ws.onText { ws, text in
                    print("Received text: \(text)")
                    self._onMessage(text)
                }
            }
            .whenComplete { [weak self] result in
                switch result {
                case .failure(let error):
                    try? self?.socketEventLoopGroup.syncShutdownGracefully()
                    reject(SwapSDKError.msg("WebSocket connection failed with error: \(error)"))
                case .success:
                    // Connection succeeded
                    print("WebSocket connection succeeded")
                    fulfill(())
                }
            }
        }
    }
    
    func disconnect() -> Promise<Void> {
        Promise { [unowned self] fulfill, reject in
            guard let ws = socket else {
                return reject(SwapSDKError.msg("Network: Socket is nil on disconnect"))
            }
            ws.close().whenComplete { _ in
                try? self.socketEventLoopGroup.syncShutdownGracefully()
                fulfill(())
            }
        }
    }
    
    func request(args: [String: String], data: [String: Any]) -> Promise<Data> {
        Promise { [unowned self] fulfill, reject in
            guard let path = args["path"] else {
                reject(SwapSDKError.msg("Invalid Path"))
                return
            }
            
            guard let url = URL(string: "http://\(config.hostName):\(config.port)\(path)") else {
                reject(SwapSDKError.msg("Invalid URL"))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = args["method"] ?? "GET"
            
            guard let id = sdk.id else {
                reject(SwapSDKError.msg("Network: missing sdk id"))
                return
            }
            
            // Convert data to JSON
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                
                // Set headers
                let creds = "\(id):\(id)"
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
                return
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    reject(error)
                } else if let data = data {
                    self.info("order created", data)
                    fulfill(data)
                } else {
                    reject(SwapSDKError.msg("No data received"))
                }
            }
            .resume()
        }
    }
    
    func send(args: [String: Any]) -> Promise<Void> {
        Promise { [unowned self] fulfill, reject in
            do {
                let dataDict = try JSONSerialization.data(withJSONObject: args, options: .prettyPrinted)
                guard let ws = socket else {
                    return reject(SwapSDKError.msg("Network: failed to send message over socket. Socket is nil"))
                }
                ws.send(dataDict.bytes)
                fulfill(())
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
