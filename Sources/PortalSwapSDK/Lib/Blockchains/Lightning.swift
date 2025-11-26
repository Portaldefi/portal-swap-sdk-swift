import Foundation
import BigInt
import Promises
import SwiftBTC
import Web3

final class Lightning: BaseClass, NativeChain {
    private let NATIVE_ASSET = "BTC"
    private let hubId: String

    private let client: ILightningClient
    
    private var subscription: InvoiceSubscription?
    
    private var activeSubscriptions: [String: Any] = [:]
    
    var queue = TransactionLock()
    
    var address: String {
        client.publickKey
    }
    
    init(props: SwapSdkConfig.Blockchains.Lightning) {
        self.client = props.client
        self.hubId = props.hubId
        
        super.init(id: "lightning")
    }
    
    func start(height: BigUInt) -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            emit(event: "start")
            
            debug("started")
        }
    }
    
    func stop() -> Promise<Void> {
        Promise { [weak self] in
            guard let self else { throw SdkError.instanceUnavailable() }
            
            emit(event: "stop")
            
            debug("stopped")
        }
    }
    
    func deposit(_ liquidity: Liquidity) -> Promise<Liquidity> {
        Promise { [weak self] in
            guard let self else {
                throw SdkError.instanceUnavailable()
            }
            if liquidity.chain != instanceId {
                let expected = instanceId
                let actual = liquidity.chain
                let ctx = ["liquidity": liquidity]
                throw NativeChainError.invalidChain(expected: expected, actual: actual, context: ctx)
            }
            
            if liquidity.symbol != NATIVE_ASSET {
                let expected = NATIVE_ASSET
                let actual = liquidity.symbol
                let ctx = ["liquidity": liquidity]
                throw NativeChainError.invalidChain(expected: expected, actual: actual, context: ctx)
            }
            
            if !liquidity.isDeposit {
                throw NativeChainError.invalidLiquidity(liquidity: try liquidity.toJSON(), metadata: [:])
            }
            
            let nativeAmount = liquidity.nativeAmount
            if nativeAmount <= 0 || nativeAmount > BigInt(Int.max) {
                throw NativeChainError.invalidAmount(nativeAmount.description)
            }
                        
            liquidity.id = Utils.createSecret().1.hexString
            let amountSat = liquidity.nativeAmount
            let liquidityString = try liquidity.toJSON()
            
            debug("deposit.started", liquidityString)
            
            let paymentId = try awaitPromise(client.payViaDetails(amountSat: amountSat, toNode: hubId, message: liquidityString))
            
            debug("deposited with paymentID", paymentId)
            
            print("LIQUIDITY PAYMENT ID: \(liquidity.notifiebleId)")
            
            subscribeForWithdrawalPayment(liquidity: liquidity)
            
            return liquidity
        }
    }
    
    private func subscribeForWithdrawalPayment(liquidity: Liquidity) {
        client.subscribeToPayment(id: liquidity.notifiebleId).then { [weak self] subscription in
            self?.subscription = subscription
            
            subscription.onInvoiceUpdated = { [weak self] status in
                switch status {
                case .paymentConfirmed:
                    subscription.off("invoice.updated")
                    self?.info("withdraw", [liquidity])
                    self?.emitOnFinality("invoice.updated", event: "withdraw", args: [liquidity])
                case .paymentFailed(let reason):
                    subscription.off("invoice.updated")
                    self?.info("deposit paiment failed")
                    self?.error("deposit payment failed", reason ?? "unknown")
                default :
                    break
                }
            }
        }
        .catch { [weak self] error in
            self?.error("subscription error", [error])
        }
    }
        
    func createInvoice(_ party: Party) -> Promise<Invoice> {
        Promise { resolve, reject in
            guard let swap = party.swap else {
                reject(SwapSDKError.msg("Failed to create invoice: swap data is missing"))
                return
            }
            
            let swapId = "0x" + swap.id
            let secretHash = String(swap.secretHash.dropFirst(2))
            let quantity = Int64(party.amount)
            
            self.client.createHodlInvoice(hash: secretHash, memo: swapId, quantity: quantity).then { [weak self] invoice in
                guard let self = self else {
                    return reject(SwapSDKError.msg("client.createHodlInvoice self is nil"))
                }
                
                guard let decodedInvoice = Bolt11.decode(string: invoice) else {
                    return reject(SwapSDKError.msg("Failed to decode invoice"))
                }
                
                guard let paymentHash = decodedInvoice.paymentHash?.hexString else {
                    return reject(SwapSDKError.msg("Decoded invoice doesn't have hash"))
                }
                
                guard paymentHash == secretHash else {
                    return reject(SwapSDKError.msg("Payment hashes doesn't match"))
                }
                
                guard decodedInvoice.description == swapId else {
                    return reject(SwapSDKError.msg("Description doesn't match"))
                }
                
                guard let decodedQuantity = decodedInvoice.amount else {
                    return reject(SwapSDKError.msg("Description doesn't match"))
                }
                
                guard decodedQuantity.int64 == quantity else {
                    return reject(SwapSDKError.msg("Quantity doesn't match"))
                }
                
                self.info("createInvoice", invoice)
                self.emit(event: "invoice.created", args: [invoice])
                
                self.client.subscribeToInvoice(id: swapId).then { [weak self] subscription in
                    guard let self = self else {
                        return reject(SwapSDKError.msg("client.subscribeToInvoice self is nil"))
                    }
                    
                    self.debug("Fetched subscription for invoice: \(swapId)")
                    
                    subscription.onInvoiceUpdated = { [weak self] status in
                        guard let self = self else {
                            return reject(SwapSDKError.msg("subscription.onInvoiceUpdated self is nil"))
                        }
                        
                        switch status {
                        case .paymentHeld:
                            self.info("invoice.paid", invoice)
                            self.emit(event: "invoice.paid", args: [swapId])
                        case .paymentConfirmed(let paymentHash):
                            party.receipt = paymentHash
                            subscription.off("invoice.updated")
                            self.info("invoice.settled", invoice)
                            try? swap.setState(.holderInvoiced)
                            try? swap.setState(.seekerInvoiced)
                            try? swap.setState(.holderPaid)
                            try? swap.setState(.seekerPaid)
                            self.emitOnFinality("invoice.updated", event: "swapSeekerPaid", args: [swap])
                        case .paymentFailed(let reason):
                            subscription.off("invoice.updated")
                            self.info("invoice.cancelled", invoice)
                            self.emit(event: "invoice.cancelled", args: [invoice])
                            self.error("Ln payment failed", reason ?? "unknown")
                        case .awaitsPayment:
                            break
                        }
                    }
                    
                    self.info("invoice.created", invoice)
                    
                    resolve(invoice)
                }
                .catch { error in
                    reject(error)
                }
            }.catch { error in
                reject(error)
            }
        }
    }
    
    func payInvoice(_ party: Party) -> Promise<Void> {
        Promise { [weak self] resolve, reject in
            guard let self = self else {
                throw SwapSDKError.msg("self is nil")
            }
            guard try party.isSecretSeeker() else {
                throw SwapSDKError.msg("Only the secret seeker can pay the invoice!")
            }
            
            guard let invoice = party.invoice else {
                throw SwapSDKError.msg("Missing invoice to pay!")
            }
            
            guard let swap = party.swap else {
                throw SwapSDKError.msg("Failed to create invoice: swap data is missing")
            }

            guard let request = Bolt11.decode(string: invoice) else {
                throw SwapSDKError.msg("Failed to decode invoice")
            }
            
            guard request.description == "0x" + swap.id else {
                throw SwapSDKError.msg("Description doesn't match")
            }
            
            guard let requestAmount = request.amount, requestAmount.description == party.amount.description else {
                throw SwapSDKError.msg("Amount mismatch")
            }
            
            debug("payInvoice", party, request)
            
            client.payViaPaymentRequest(swapId: swap.id, request: invoice).then { result in
                party.receipt = result.id
                
                self.client.subscribeToPayment(id: result.id).then { [weak self] subscription in
                    guard let self = self else {
                        return reject(SwapSDKError.msg("client.subscribeToInvoice self is nil"))
                    }
                    
                    self.debug("Fetched subscription for invoice: \(swap.id)")
                    
                    subscription.onInvoiceUpdated = { [weak self] status in
                        guard let self = self else {
                            return reject(SwapSDKError.msg("subscription.onInvoiceUpdated self is nil"))
                        }
                                                
                        switch status {
                        case .paymentConfirmed(let secret):
                            subscription.off("invoice.updated")
                            
                            self.info("invoice.paid", [
                                "invoice": invoice,
                                "secret": secret
                            ])

                            if let secret {
                                let holderSettled = HolderSettledSwap(id: swap.id, secret: Data(hex: secret))
                                self.info("swapHolderSettled", holderSettled)
                                self.emitOnFinality("invoice.updated", event: "swapHolderSettled", args: [holderSettled])
                            } else {
                                return reject(SwapSDKError.msg("secret is missing"))
                            }
                        case .paymentFailed(let reason):
                            subscription.off("invoice.updated")
                            self.info("invoice.cancelled", invoice)
                            self.emit(event: "invoice.cancelled", args: [invoice])
                            self.error("Ln payment failed", reason ?? "unknown")
                        case .paymentHeld, .awaitsPayment:
                            break
                        }
                    }
                                        
                    let seekerPaid = SeekerPaidSwap(id: swap.id, secretSeeker: result.id)
                    self.info("swapSeekerPaid", seekerPaid)
                    self.emitOnFinality("invoice.updated", event: "swapSeekerPaid", args: [seekerPaid])
                }
            }.catch { error in
                reject(error)
            }
        }
    }
    
    func settleInvoice(for party: Party, with secret: Data) -> Promise<Party> {
        Promise { [weak self] resolve, reject in
            guard let self = self else {
                return reject(SwapSDKError.msg("self is nil"))
            }
            client.settleHodlInvoice(secret: secret).then { response in
                try party.swap?.setState(.holderSettled)
                try party.swap?.setSecret(secret)
                self.emitOnFinality("invoice.updated", event: "swapHolderSettled", args: [party.swap!])
                resolve(party)
            }.catch { error in
                reject(error)
            }
        }
    }
    
    func getBlockHeight() -> Promise<UInt64> {
        //FIXME: implement proper block height fetching
        Promise { UInt64(0) }
    }
}

extension Lightning: TxLockable {
    internal func waitForReceipt(txid: String) -> Promise<Void> {
        withTxLock {
            Promise { resolve, reject in
                DispatchQueue.sdk.asyncAfter(deadline: .now() + 2.0) {
                    resolve(())
                }
            }
        }
    }
}
