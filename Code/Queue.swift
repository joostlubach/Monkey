import Foundation

public enum OperationStatus {

  case ready
  case running
  case finished
  case cancelled

}

public enum QueueStatus {

  case stopped
  case running

}

protocol Operation: class {

  var status: OperationStatus { get }

  func start()
  func cancel()

  var completion: (() -> Void)? { get set }

}

/**
Manages a set of operations and executes them in order.
*/
class OperationQueue {

  /// Determines how many operations may be running at the same time.
  var maxConcurrency = 3

  /// The status of the queue.
  var status = QueueStatus.stopped

  /// The queued operations.
  fileprivate(set) var queued = [Operation]()

  /// The currently running operations.
  fileprivate(set) var running = [Operation]()

  var count: Int {
    return queued.count + running.count
  }

  /**
  Enqueues an operation.
  
  - parameter operation:  The operation to enqueue.
  */
  func enqueue(_ operation: Operation) {
    queued.append(operation)

    if status == .stopped {
      start()
    }
  }

  /**
  Dequeues an operation.

  - parameter operation:  The operation to dequeue.
  - returns:          Whether the operation was dequeued. If the operation was not queued in the first place,
                     this value will be false.
  */
  func dequeue(_ operation: Operation) -> Bool {
    for idx in 0..<queued.count {
      if queued[idx] === operation {
        queued.remove(at: idx)
        return true
      }
    }
    return false
  }

  /// Starts the queue. If it was already running, this will do nothing.
  func start() {
    if status == .running {
      return
    }

    status = .running
    next()
  }

  /**
  Stops the queue and cancels all running operations. Queued operations will remain and will be started
  again when `start()` is called. If the queue was already stopped, this will do nothing.
  */
  func stop() {
    if status == .stopped {
      return
    }

    status = .stopped

    for operation in running {
      operation.cancel()
    }
    running = []
  }

  /// Starts the next operation in the queue.
  fileprivate func next() {
    if status == .stopped {
      return
    }

    // If no more operations are running or queued, stop the queue.
    if count == 0 {
      stop()
    }

    // If no more operations are queued, or we cannot run more operations, return.
    if queued.count == 0 || running.count >= maxConcurrency {
      return
    }

    // Start
    let operation = queued.remove(at: 0)

    switch operation.status {
    case .running:
      // Output a warning, and don't run the operation again.
      print("Monkey.Queue: operation already running")
    case .finished:
      // Output a warning, and don't run the operation again.
      print("Monkey.Queue: operation already finished")
    default:
      running.append(operation)
      operation.completion = { [weak self, unowned operation] in
        self?.operationComplete(operation)
      }
      operation.start()
    }

    // Immediately queue the next until the maximum concurrency has been reached.
    next()
  }

  /// Called when an operation is completed.
  fileprivate func operationComplete(_ operation: Operation) {
    for idx in 0..<running.count {
      if running[idx] === operation {
        running.remove(at: idx)
        break
      }
    }

    // Start running a next operation.
    next()
  }


}
