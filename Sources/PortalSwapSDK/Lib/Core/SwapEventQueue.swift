import Foundation

struct QueuedEvent {
    let swapDiff: SwapDiff
    let timestamp: Date
}

final class SwapEventQueue {
    private var queues: [String: [QueuedEvent]] = [:]  // swapId -> events
    private let maxQueueTime: TimeInterval = 5 * 60    // 5 minutes
    
    private func isSequentialTransition(current: SwapState, target: SwapState) -> Bool {
        return target.rawValue == current.rawValue + 1
    }
    
    func enqueue(swap: Swap, swapDiff: SwapDiff) -> (canProcess: Bool, reason: String?) {
        let currentState = swap.state
        let targetState = swapDiff.state
        
        // Valid sequential transition - process immediately
        if isSequentialTransition(current: currentState, target: targetState) {
            return (true, nil)
        }
        
        // Old/duplicate event - ignore
        if targetState.rawValue <= currentState.rawValue {
            return (false, "Ignoring old/duplicate event: current=\(currentState), target=\(targetState)")
        }
        
        // Out-of-order event - queue it
        var queue = queues[swap.id] ?? []
        queue.append(QueuedEvent(swapDiff: swapDiff, timestamp: Date()))
        queue.sort { $0.swapDiff.state.rawValue < $1.swapDiff.state.rawValue }
        queues[swap.id] = queue
        
        return (false, "Out-of-order event queued: current=\(currentState), target=\(targetState)")
    }
    
    func processQueue(swap: Swap) -> [SwapDiff] {
        guard var queue = queues[swap.id], !queue.isEmpty else {
            return []
        }
        
        var readyEvents: [SwapDiff] = []
        var currentState = swap.state
        let now = Date()
        
        // Remove expired events
        queue = queue.filter { now.timeIntervalSince($0.timestamp) <= maxQueueTime }
        
        var i = 0
        while i < queue.count {
            let event = queue[i]
            
            if isSequentialTransition(current: currentState, target: event.swapDiff.state) {
                readyEvents.append(event.swapDiff)
                currentState = event.swapDiff.state
                queue.remove(at: i)
            } else if event.swapDiff.state.rawValue <= currentState.rawValue {
                queue.remove(at: i)  // Obsolete event
            } else {
                i+=1  // Still waiting
            }
        }
        
        if queue.isEmpty {
            queues.removeValue(forKey: swap.id)
        } else {
            queues[swap.id] = queue
        }
        
        return readyEvents
    }
    
    func clear(swapId: String) {
        queues.removeValue(forKey: swapId)
    }
    
    func getQueueSize(swapId: String) -> Int {
        queues[swapId]?.count ?? 0
    }
}
