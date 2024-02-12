# portal-swap-sdk-swift
Portal cross-chain atomic swap SDK for Swift apps

## Installation
### Swift Package Manager
To install using Swift Package Manager, add the following line to the depedencies array of your `Package.swift`:
```
.package(url: "https://github.com/Portaldefi/portal-swap-sdk-swift", branch: "main")
```
### Import
```
import PortalSwapSDK
```
## Configuration
Configure the SDK by setting up the network and blockchain-specific parameters:
### Network Configuration
```
let network = SwapSdkConfig.Network(
  networkProtocol: .encrypted,
  hostname: "node.playnet.portaldefi.zone",
  port: 1337
)
```
### Ethereum Configuration
```
let ethereum = SwapSdkConfig.Blockchains.Ethereum(
    url: "wss://sepolia.gateway.tenderly.co",
    chainId: "0xaa36a7",
    contracts: contracts,
    privKey: ethPrivKey
)
```
### Lightning Network Configuration
Implement the 'ILightningClient' protocol for Lightning actions
```
protocol ILightningClient {
    func createHodlInvoice(hash: String, memo: String, quantity: Int64) -> Promise<String>
    func subscribeToInvoice(id: String) -> Promise<InvoiceSubscription>
    func payViaPaymentRequest(swapId: String, request: String) -> Promise<PaymentResult>
    func settleHodlInvoice(secret: Data) -> Promise<[String:String]>
}
```
### Initialize SDK
```
let lightning: ILightningClient = LightningClient()
let blockchains = SwapSdkConfig.Blockchains(ethereum: ethereum, lightning: lightning)
let sdkConfig = SwapSdkConfig(
    id: UUID().uuidString,
    network: network,
    blockchains: blockchains
)
let sdk = SDK.init(config: sdkConfig)
```
## Usage
### Start
```
sdk.start()
```
### Stop
```
sdk.stop()
```
### Placing order
```
let order = OrderRequest(
    baseAsset: "BTC",
    baseNetwork: "lightning.btc",
    baseQuantity: baseQuantity, // Int
    quoteAsset: "ETH",
    quoteNetwork: "ethereum",
    quoteQuantity: quoteQuantity, // Int
    side: orderSide.rawValue
)

sdk.submitLimitOrder(order).then { order in
    // Handle order
}
```
### Canceling an Order
```
sdk.cancelLimitOrder(order).then { _ in
    // Handle order canceled
}
```
### Subscribing to SDK Events
```
sdk.addListener(event: "swap.received", action: { _ in
    // Handle swap received event
})

sdk.addListener(event: "swap.completed", action: { _ in
    // Handle swap completed event
})

sdk.addListener(event: "error", action: { args in
    // Handle swap completed event
    // error message in args.first
})
```
### Fetching Swap models
```
let persistenceManager = try LocalPersistenceManager.manager()
let swaps = try manager.fetchSwaps()
```

