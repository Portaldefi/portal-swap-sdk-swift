import Foundation
import Promises

struct PaymentReceipt {
    let id: String
    let expiresAt: Date
    let payment: String
}

struct DecodedPaymentRequest {
    let id: String
    let description: String
    let tokens: Int
}

class Lightning: BaseClass {
    private let sdk: Sdk
    private let client: ILightningClient
    
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Lightning) {
        self.sdk = sdk
        self.client = props.client
        super.init(id: "Lightning")
    }
    
    func connect() -> Promise<Lightning> {
        emit(event: "connect")
        
        return Promise {
            self
        }
    }
    
    func disconnect() -> Promise<Lightning> {
        Promise {
            self
        }
    }
    
    func createInvoice(party: Party) throws -> Promise<(id: String, description: String, request: String)> {
        let swap = party.swap!
        let description = swap.id!
        let id = swap.secretHash!
        let tokens = party.quantity
        
        return Promise {
            self.client.createInvoice(id: id, description: description, tokens: tokens)
                .then { invoice in
                    self.info("createInvoice", [invoice])
                    self.emit(event: "invoice.created", args: [invoice])
                    
                    self.client.subscribeToInvoice(id: id).then { subscription in
                        subscription.onInvoiceUpdated = { [weak self] invoice in
                            guard let strongSelf = self else { return }
                            if invoice.isHeld {
                                strongSelf.info("invoice.paid", invoice)
                                strongSelf.emit(event: "invoice.paid", args: [invoice])
                            } else if invoice.isConfirmed {
                                subscription.off("invoice_updated")
                                strongSelf.info("invoice.settled", invoice)
                                strongSelf.emit(event: "invoice.settled", args: [invoice])
                            } else if invoice.isCanceled {
                                subscription.off("invoice_updated")
                                strongSelf.info("invoice.cancelled", invoice)
                                strongSelf.emit(event: "invoice.cancelled", args: [invoice])
                            }
                        }
                        
                        self.info("invoice.created", invoice)
                        
                        return (id, description, invoice)
                    }
                }
        }
    }
    
    func payInvoice(party: Party) -> Promise<Void> {
        let request = party.invoice!
        let expectedSecretHash = party.swap!.secretHash
        let expectedDescription = party.swap!.id
        let expectedQuantity = party.quantity
        
        return Promise<Void> {
            self.client.decodePaymentRequest(request: request).then { decodedRequest in
                // Validation of the invoice
                guard decodedRequest.string == expectedSecretHash else {
                    throw NSError(domain: "Validation", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected swap hash \(String(describing: expectedSecretHash)); got \(decodedRequest)"])
                }
                
                guard decodedRequest.description == expectedDescription else {
                    throw NSError(domain: "Validation", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected swap identifier \(String(describing: expectedDescription)); got \(decodedRequest.description)"])
                }
                
                guard decodedRequest.tokens == expectedQuantity else {
                    throw NSError(domain: "Validation", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected swap quantity \(expectedQuantity); got \(decodedRequest.tokens)"])
                }
                
                // Pay the invoice
                _ = self.client.payViaPaymentRequest(request: request)
            
                self.info("payInvoice", decodedRequest)
                
                return PaymentReceipt(id: expectedDescription!, expiresAt: Date(), payment: String())
            }
        }
    }
    
    func settleInvoice(party: Party, secret: String) -> Promise<Void> {
        Promise {()}
    }
    
}
