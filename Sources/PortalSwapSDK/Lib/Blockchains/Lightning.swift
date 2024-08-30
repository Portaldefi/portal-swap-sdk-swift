import Foundation
import BigInt
import Promises
import SwiftBTC
import Web3

final class Lightning: BaseClass, IBlockchain {
    private let sdk: Sdk
    private let client: ILightningClient
    //sdk seems unused
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Lightning) {
        self.sdk = sdk
        self.client = props.client
        
        super.init(id: "Lightning")
    }
    
    func connect() -> Promise<Void> {
        emit(event: "connect")
        return Promise { () }
    }
    
    func disconnect() -> Promise<Void> {
        emit(event: "disconnect")
        return Promise { () }
    }
    
    func create(invoice: [String: String]) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            guard 
                let swapId = invoice["swapId"],
                let secretHash = invoice["secretHash"],
                let quantityString = invoice["quantity"],
                let quantity = Int64(quantityString)
            else {
                return reject(SwapSDKError.msg("Failed to create invoice: swap data is missing"))
            }
            
            client.createHodlInvoice(hash: secretHash, memo: swapId, quantity: quantity).then { [weak self] invoice in
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
                        case .paymentConfirmed:
                            subscription.off("invoice.updated")
                            self.info("invoice.settled", invoice)
                            self.emit(event: "invoice.settled", args: [swapId])
                        case .paymentCanceled:
                            subscription.off("invoice.updated")
                            self.info("invoice.cancelled", invoice)
                            self.emit(event: "invoice.cancelled", args: [invoice])
                        case .awaitsPayment:
                            break
                        }
                    }
                    
                    self.info("invoice.created", invoice)
                    
                    resolve(["id": secretHash, "swap": swapId, "request": invoice])
                }
                .catch { error in
                    reject(error)
                }
            }.catch { error in
                reject(error)
            }
        }
    }
    
    func pay(invoice: [String: String]) -> Promise<[String: Any]> {
        Promise { [unowned self] resolve, reject in
            guard let swapId = invoice["swapId"], let request = invoice["request"] else {
                return reject(SwapSDKError.msg("swapId is missing on payInvoice"))
            }
                                    
            decodePayment(request: request).then { [weak self] paymentRequest in
                guard let self = self else {
                    return reject(SwapSDKError.msg("decodePaymentRequest(party: ) self is nil"))
                }
                
//                if paymentRequest.id != swap.secretHash {
//                    let actual = paymentRequest.id
//                    reject(SwapSDKError.msg("expected swap hash \(swap.secretHash), got \(actual)"))
//                } else if paymentRequest.swap.id != swap.swapId {
//                    let actual = paymentRequest.swap.id
//                    reject(SwapSDKError.msg("expected swap identifier \(swap.swapId), got \(actual)"))
//                } else if paymentRequest.amount != party.quantity {
//                    let expected = party.quantity
//                    let actual = paymentRequest.swap.id
//                    reject(SwapSDKError.msg("expected swap quantuty \(expected), got \(actual)"))
//                }
                
                let invoice = paymentRequest.request

                self.client.payViaPaymentRequest(swapId: swapId, request: invoice).then { [weak self] result in
                    
                    guard let self = self else {
                        return reject(SwapSDKError.msg("client.payViaPaymentRequest(swapId: ) self is nil"))
                    }
                    
                    self.info("payInvoice", ["result": result])
                    
                    self.client.subscribeToPayment(id: result.id).then { [weak self] subscription in
                        guard let self = self else {
                            return reject(SwapSDKError.msg("client.subscribeToInvoice self is nil"))
                        }
                        
                        self.debug("Fetched subscription for invoice: \(swapId)")
                        
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
                                    self.emit(event: "invoice.paid", args: [swapId, secret, result.memo])
                                } else {
                                    self.emit(event: "invoice.paid", args: [swapId])
                                }
                            case .paymentCanceled:
                                subscription.off("invoice.updated")
                                self.info("invoice.cancelled", invoice)
                                self.emit(event: "invoice.cancelled", args: [invoice])
                            case .paymentHeld, .awaitsPayment:
                                break
                            }
                        }
                        
                        self.info("invoice.created", invoice)
                    }
                    
                    
                    let receipt = [
                        "id": result.id,
                        "swap": [
                            "id": result.swap.id
                        ],
                        "request": result.request,
                        "amount": result.amount
                    ]
                    resolve(receipt)
                }.catch { [weak self] error in
                    self?.error("PayViaPaymentRequest", [error, paymentRequest])
                    self?.emit(event: "error", args: [error, paymentRequest])
                    reject(SwapSDKError.msg("Cannot pay lightning invoice: \(error)"))
                }
            }.catch { error in
                reject(error)
            }
        }
    }
    
    private func decodePayment(request: String) -> Promise<PaymentResult> {
        Promise { resolve, reject in
            guard let bolt11Invoice = Bolt11.decode(string: request) else {
                return reject(SwapSDKError.msg("Cannot decode request"))
            }
            
            guard let paymentHash = bolt11Invoice.paymentHash else {
                return reject(SwapSDKError.msg("Invoice has no payment hash"))
            }
            
            guard let swapId = bolt11Invoice.description else {
                return reject(SwapSDKError.msg("Invoice has no description"))
            }
            
            guard let amount = bolt11Invoice.amount else {
                return reject(SwapSDKError.msg("Invoice has no amount"))
            }
            
            let decodedRequest = PaymentResult(
                id: paymentHash.hexString,
                swap: PaymentResult.Swap(id: swapId),
                request: request,
                amount: amount.int64, 
                memo: String()
            )
            
            resolve(decodedRequest)
        }
    }
        
    func settle(invoice: [String: String], secret: Data) -> Promise<[String: String]> {
        client.settleHodlInvoice(secret: secret)
    }
}
