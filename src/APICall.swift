import Foundation
import Alamofire
import BrightFutures
import SwiftyJSON

/**
 * API call.
 */
public class APICall: Operation {

  public typealias ProgressBlock = (current: Int64, total: Int64) -> Void

  /**
  Initializes an API request with a URL request.

  - parameter client:      The API client making the request (stored as a weak reference).
  - parameter request:     The URL request to make.
  */
  init(client: APIClient, request: NSMutableURLRequest, authenticate: Bool = true) {
    self.client = client
    self.authenticate = authenticate
    self.request = request
  }

  /// The client making the request.
  public weak var client: APIClient?

  public let request: NSMutableURLRequest

  public private(set) var status = OperationStatus.Ready

  /// The Alamofire request backing this operation.
  var alamofireRequest: Alamofire.Request?

  /// The current try count for this operation.
  public private(set) var retryCount: Int = 1

  /// The response. Only available when the operation is complete.
  public private(set) var response: APIResponse?

  /// Can be set to a block which will receive upload/download progress.
  public var progressBlock: ProgressBlock?

  /// A completion block.
  var completion: (() -> Void)?

  // MARK: Response handlers

  typealias ResponseHandler = (APIResponse) -> Void
  typealias FinallyHandler = () -> Void

  private var responseHandlers = [ResponseHandler]()
  private var finallyHandlers = [FinallyHandler]()

  private let promise = Promise<APIResponse, NSError>()

  /// Adds a response handler, which is called upon any result (success or failure).
  public func response(handler: (APIResponse) -> Void) {
    responseHandlers.append(handler)
  }

  /// Adds a finally handler, which is called after all response handlers have been processed.
  public func finally(handler: () -> Void) {
    finallyHandlers.append(handler)
  }

  /// Adds a response handler, which is called upon success.
  public func responseSuccess(handler: (APIResponse) -> Void) {
    response { response in
      if response.type == .Success {
        handler(response)
      }
    }
  }
  
  /// Adds a response handler, which is called upon error.
  public func responseError(handler: (APIResponse, NSError) -> Void) {
    response { response in
      if response.type != .Success {
        handler(response, response.error!)
      }
    }
  }

  /// Adds a data handler, which is called when the call succeeds, passing the raw data.
  public func data(handler: (NSData) -> Void) {
    responseSuccess { response in
      response.whenData(handler)
    }
  }

  /// Adds a JSON handler, which is called when the call succeeds, and the response contained JSON.
  public func json(handler: (JSON) -> Void) {
    responseSuccess { response in
      response.whenJSON(handler)
    }
  }

  public var future: Future<APIResponse, NSError> {
    return promise.future
  }

  public var jsonFuture: Future<JSON, NSError> {
    let promise = Promise<JSON, NSError>()

    self.promise.future.onSuccess { response in
      if let json = response.json {
        promise.success(json)
      } else {
        let error = NSError(domain: Monkey.ErrorDomain, code: Monkey.ErrorCodes.InvalidJSON.rawValue, userInfo: nil)
        promise.failure(error)
      }
    }
    promise.future.onFailure { error in
      promise.failure(error)
    }

    return promise.future
  }

  // MARK: Authentication

  /// Determines whether the request should be authenticated before it is started.
  public var authenticate: Bool = true

  /// Authenticates the current request.
  private func authenticateRequest() {
    client?.session?.authenticateRequest(request)
  }

  // MARK: Start & cancel

  public func start() {
    if status == .Cancelled {
      return
    }


    // Authenticate the request if required.
    if authenticate { authenticateRequest() }

    alamofireRequest = buildAlamofireRequest()

    // Trace this request in the logger.
    client?.traceRequest(request)

    // Handle progress.
    alamofireRequest!.progress { [weak self] _, current, total in
      self?.progressBlock?(current: current, total: total)
    }

    alamofireRequest!.response { [weak self] _, httpResponse, data, error in
      if let operation = self {
        operation.handleResponse(httpResponse, data: data, error: error as? NSError)
      }
    }

    status = .Running
  }

  public func cancel() {
    alamofireRequest?.cancel()
    status = .Cancelled
  }

  public func retry() {
    if status == .Cancelled {
      retryCount += 1
      status = .Ready
    }
  }

  private func buildAlamofireRequest() -> Alamofire.Request {
    return Alamofire.Manager.sharedInstance.request(request)
  }

  private func handleResponse(httpResponse: NSHTTPURLResponse?, data: NSData?, error: NSError?) {
    // Store the response and handle it.
    let response = APIResponse(client: client, httpResponse: httpResponse, data: data)
    self.response = response

    if authenticate && response.type == .NotAuthorized {

      // Perform an authenticate & retry.
      if retryCount < 3, let client = self.client {
        client.trace("-> Authenticating & retrying")
        client.authenticateAndRetry(self)
      } else {
        client?.trace("-> Giving up")
      }
    } else {

      // Call all response handlers.
      Queue.main.async {
        for handler in self.responseHandlers {
          handler(response)
        }
      }

      // Also resolve the promise.
      if response.type == .Success {
        promise.success(response)
      } else {
        promise.failure(error ?? response.error!)
      }

      // Call the finally handlers.
      Queue.main.async {
        for handler in self.finallyHandlers {
          handler()
        }
      }
    }

    alamofireRequest = nil
    completion?()
  }

}

public class APIUpload: APICall {

  private override func buildAlamofireRequest() -> Alamofire.Request {
    return Alamofire.Manager.sharedInstance.upload(request, data: request.HTTPBody!)
  }

}