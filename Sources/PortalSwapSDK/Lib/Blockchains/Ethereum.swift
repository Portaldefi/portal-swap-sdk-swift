import Foundation
import Promises

class Ethereum: BaseClass {
    
    // Sdk seems unuaed
    init(sdk: Sdk, props: SwapSdkConfig.Blockchains.Ethereum) {
        super.init(id: "Ethereum")

    }
    
    // Initializes the connection to the geth daemon
    func connect() -> Promise<Ethereum> {
        emit(event: "connect")
        
        return Promise {
            return self
        }
//        try {
//            this.emit('connect', this)
//            return this
//        } catch (err) {
//            this.error('connect', err, this)
//            throw err
//        }
    }
    
    func disconnect() -> Promise<Ethereum> {
        Promise {
            return self
        }
//        return new Promise((resolve, reject) => {
//            const { web3: { provider }, events } = INSTANCES.get(this)
//            events.unsubscribe()
//                .then(() => {
//                    provider.once('disconnect', () => {
//                        this.emit('disconnect', this)
//                        resolve()
//                    })
//                    provider.once('error', err => {
//                        this.error('disconnect', err, this)
//                        reject(err)
//                    })
//                    provider.disconnect()
//                })
//                .catch(reject)
//        })
//    }
    }

    
    func createInvoice(party: Party) -> Promise<Invoice> {
        Promise {Invoice()}
    }
    
    func payInvoice(party: Party) -> Promise<Void> {
        Promise {()}
        
//        try {
//            const { web3, contract } = INSTANCES.get(this)
//            const { methods: { payInvoice } } = contract
//            const { toHex } = web3.utils
//
//            const id = toHex(party.swap.secretHash)
//            const swap = toHex(party.swap.id)
//            const asset = '0x0000000000000000000000000000000000000000'
//            const value = toHex(party.quantity)
//
//            const tx = payInvoice(id, swap, asset, value)
//            // TODO: fix value to only be used for ETH transactions
//            const gas = await tx.estimateGas({ value })
//            const receipt = await tx.send({ gas, value })
//
//            this.info('payInvoice', receipt, party, this)
//            // TODO: This should be an Invoice object
//            return null
//        } catch (err) {
//            this.error('payInvoice', err, party, this)
//            throw err
//        }
    }
    
    func settleInvoice(party: Party, secret: String) -> Promise<Void> {
        Promise {()}
        
//        try {
//            const { web3, contract } = INSTANCES.get(this)
//            const { methods: { settleInvoice } } = contract
//            const { toHex } = web3.utils
//
//            const swap = toHex(party.swap.id)
//            const tx = settleInvoice(`0x${secret}`, swap)
//            const gas = await tx.estimateGas()
//            const receipt = await tx.send({ gas })
//
//            this.info('settleInvoice', receipt, party, this)
//            // TODO: This should be an Invoice object
//            return null
//        } catch (err) {
//            this.error('settleInvoice', err, party, this)
//            throw err
//        }
    }
}
