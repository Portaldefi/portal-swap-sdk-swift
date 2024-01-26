import Foundation
import Promises
import SwiftBTC

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
    
    func createInvoice(party: Party) -> Promise<[String: String]> {
        Promise { [unowned self] resolve, reject in
            guard let id = party.swap?.swapId, let secretHash = party.swap?.secretHash else {
                return reject(SwapSDKError.msg("Failed to create invoice: swap data is missing"))
            }
            
            let quantity = party.quantity
            
            client.createHodlInvoice(hash: secretHash, memo: id, quantity: quantity).then { [weak self] invoice in
                guard let self = self else {
                    return reject(SwapSDKError.msg("client.createHodlInvoice self is nil"))
                }
                
                guard let decodedInvoice = Bolt11.decode(string: invoice) else {
                    return reject(SwapSDKError.msg("Failed to decode invoice"))
                }
                
                guard let paymentHash = decodedInvoice.paymentHash?.toHexString() else {
                    return reject(SwapSDKError.msg("Decoded invoice doesn't have hash"))
                }
                
                guard paymentHash == secretHash else {
                    return reject(SwapSDKError.msg("Payment hashes doesn't match"))
                }
                
                guard decodedInvoice.description == id else {
                    return reject(SwapSDKError.msg("Description doesn't match"))
                }
                
                guard let decodedQuantity = decodedInvoice.amount else {
                    return reject(SwapSDKError.msg("Description doesn't match"))
                }
                
                guard decodedQuantity.int64 == quantity else {
                    return reject(SwapSDKError.msg("Quantity doesn't match"))
                }
                                
                self.info("createInvoice", "partyId: \(party.id)", invoice)
                self.emit(event: "invoice.created", args: [invoice])
                
                self.client.subscribeToInvoice(id: id).then { [weak self] subscription in
                    guard let self = self else {
                        return reject(SwapSDKError.msg("client.subscribeToInvoice self is nil"))
                    }
                    
                    self.debug("Fetched subscription for invoice: \(id)")
                    
                    subscription.onInvoiceUpdated = { [weak self] status in
                        guard let self = self else {
                            return reject(SwapSDKError.msg("subscription.onInvoiceUpdated self is nil"))
                        }
                                                
                        switch status {
                        case .paymentHeld:
                            self.info("invoice.paid", "partyId: \(party.id)", invoice)
                            self.emit(event: "invoice.paid", args: [invoice])
                        case .paymentConfirmed:
                            subscription.off("invoice.updated")
                            self.info("invoice.settled", "partyId: \(party.id)", invoice)
                            self.emit(event: "invoice.settled", args: [invoice])
                        case .paymentCanceled:
                            subscription.off("invoice.updated")
                            self.info("invoice.cancelled", "partyId: \(party.id)", invoice)
                            self.emit(event: "invoice.cancelled", args: [invoice])
                        case .awaitsPayment:
                            break
                        }
                    }
                    
                    self.info("invoice.created", "partyId: \(party.id)", invoice)
                    
                    resolve(["id": secretHash, "swap": id, "request": invoice])
                }
                .catch { error in
                    reject(error)
                }
            }.catch { error in
                reject(error)
            }
        }
    }
    
    func payInvoice(party: Party) -> Promise<[String: Any]> {
        Promise { [unowned self] resolve, reject in
            guard let swap = party.swap else {
                return reject(SwapSDKError.msg("Party has no swap"))
            }
            
            guard let secretHash = swap.secretHash else {
                return reject(SwapSDKError.msg("Swap has no secret hash"))
            }
                        
            decodePaymentRequest(party: party).then { [weak self] paymentRequest in
                guard let self = self else {
                    return reject(SwapSDKError.msg("decodePaymentRequest(party: ) self is nil"))
                }
                
                if paymentRequest.id != secretHash {
                    let actual = paymentRequest.id
                    reject(SwapSDKError.msg("expected swap hash \(secretHash), got \(actual)"))
                } else if paymentRequest.swap.id != swap.swapId {
                    let actual = paymentRequest.swap.id
                    reject(SwapSDKError.msg("expected swap identifier \(swap.swapId), got \(actual)"))
                } else if paymentRequest.amount != party.quantity {
                    let expected = party.quantity
                    let actual = paymentRequest.swap.id
                    reject(SwapSDKError.msg("expected swap quantuty \(expected), got \(actual)"))
                }

                self.client.payViaPaymentRequest(swapId: swap.swapId, request: paymentRequest.request).then { [weak self] result in
                    
                    guard let self = self else {
                        return reject(SwapSDKError.msg("client.payViaPaymentRequest(swapId: ) self is nil"))
                    }
                    
                    self.info("payViaPaymentRequest", "partyId: \(party.id)", result)
                    
                    let reciep = [
                        "id": result.id,
                        "swap": [
                            "id": result.swap.id
                        ],
                        "request": result.request,
                        "amount": result.amount
                    ]
                    resolve(reciep)
                }.catch { error in
                    self.error("PayViaPaymentRequest", [error, paymentRequest, party])
                    self.emit(event: "error", args: [error, paymentRequest, party])
                    reject(SwapSDKError.msg("Cannot pay lightning invoice: \(error)"))
                }
            }.catch { error in
                reject(error)
            }
        }
    }
    
    private func decodePaymentRequest(party: Party) -> Promise<PaymentResult> {
        Promise { resolve, reject in
            guard let invoice = party.invoice, let request = invoice["request"] else {
                return reject(SwapSDKError.msg("Party has no invoice"))
            }
            
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
                id: paymentHash.toHexString(),
                swap: PaymentResult.Swap(id: swapId),
                request: request,
                amount: amount.int64
            )
            
            resolve(decodedRequest)
        }
    }
    
    func settleInvoice(party: Party, secret: Data) -> Promise<[String: String]> {
        client.settleHodlInvoice(secret: secret)
    }
}
