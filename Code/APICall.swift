import Foundation
import Alamofire
import BrightFutures
import SwiftyJSON

/**
 * API call.
 */
open class APICall: Operation {

  public typealias ProgressBlock = (_ current: Int64, _ total: Int64) -> Void

  /**
  Initializes an API request with a URL request.

  - parameter client:      The API client making the request (stored as a weak reference).
  - parameter request:     The URL request to make.
  */
  init(client: APIClient, request: URLRequest, authenticate: Bool = true) {
    self.client = client
    self.authenticate = authenticate
    self.request = request
  }

  /// The client making the request.
  open unowned let client: APIClient

  open private(set) var request: URLRequest

  open private(set) var status = OperationStatus.ready

  /// The Alamofire request backing this operation.
  var alamofireRequest: Alamofire.Request?

  /// The current try count for this operation.
  open private(set) var retryCount: Int = 1

  /// The response. Only available when the operation is complete.
  open private(set) var response: APIResponse?

  /// Can be set to a block which will receive upload/download progress.
  open var progressBlock: ProgressBlock?

  /// A completion block.
  var completion: (() -> Void)?

  // MARK: Response handlers

  typealias ResponseHandler = (APIResponse) -> Void
  typealias FinallyHandler = () -> Void

  private var responseHandlers = [ResponseHandler]()
  private var finallyHandlers = [FinallyHandler]()

  private let promise = Promise<APIResponse, APIError>()

  /// Adds a response handler, which is called upon any result (success or failure).
  open func response(_ handler: @escaping (APIResponse) -> Void) {
    responseHandlers.append(handler)
  }

  /// Adds a finally handler, which is called after all response handlers have been processed.
  open func finally(_ handler: @escaping () -> Void) {
    finallyHandlers.append(handler)
  }

  /// Adds a response handler, which is called upon success.
  open func responseSuccess(_ handler: @escaping (APIResponse) -> Void) {
    response { response in
      response.whenSuccess(handler)
    }
  }
  
  /// Adds a response handler, which is called upon error.
  open func responseError(_ handler: @escaping (APIError) -> Void) {
    response { response in
      response.whenError(handler)
    }
  }

  /// Adds a response handler, which is called upon error of a specific type.
  open func responseErrorOfType(_ errorType: APIErrorType, handler: @escaping (APIError) -> Void) {
    response { response in
      response.whenErrorOfType(errorType, block: handler)
    }
  }

  /// Adds a data handler, which is called when the call succeeds, passing the raw data.
  open func data(_ handler: @escaping (Data) -> Void) {
    responseSuccess { response in
      response.whenData(handler)
    }
  }

  /// Adds a JSON handler, which is called when the call succeeds, and the response contained JSON.
  open func json(_ handler: @escaping (JSON) -> Void) {
    responseSuccess { response in
      response.whenJSON(handler)
    }
  }

  open var future: Future<APIResponse, APIError> {
    return promise.future
  }

  open var jsonFuture: Future<JSON, APIError> {
    let promise = Promise<JSON, APIError>()

    self.promise.future.onSuccess { response in
      if let json = response.json {
        promise.success(json)
      } else {
        promise.failure(APIError(type: .invalidData))
      }
    }
    self.promise.future.onFailure { error in
      promise.failure(error)
    }

    return promise.future
  }

  // MARK: Authentication

  /// Determines whether the request should be authenticated before it is started.
  open var authenticate: Bool = true

  /// Authenticates the current request.
  private func authenticateRequest() {
    guard let session = client.session else { return }
    request = session.authenticateRequest(request)
  }

  // MARK: Start & cancel

  open func start() {
    if status == .cancelled {
      return
    }


    // Authenticate the request if required.
    if authenticate { authenticateRequest() }

    alamofireRequest = buildAlamofireRequest()

    // Trace this request in the logger.
    client.traceRequest(request as URLRequest)

    // Handle progress.
    if let dataRequest = alamofireRequest as? DataRequest {
      dataRequest.downloadProgress { [weak self] progress in
        self?.progressBlock?(progress.completedUnitCount, progress.totalUnitCount)
      }

      dataRequest.response { [weak self] response in
        self?.handleResponse(response.response, data: response.data, error: response.error)
      }
    }
    if let downloadRequest = alamofireRequest as? DownloadRequest {
      downloadRequest.downloadProgress { [weak self] progress in
        self?.progressBlock?(progress.completedUnitCount, progress.totalUnitCount)
      }

      downloadRequest.response { [weak self] response in
        self?.handleResponse(response.response, data: response.resumeData, error: response.error)
      }
    }
    if let uploadRequest = alamofireRequest as? UploadRequest {
      uploadRequest.uploadProgress { [weak self] progress in
        self?.progressBlock?(progress.completedUnitCount, progress.totalUnitCount)
      }

      uploadRequest.response { [weak self] response in
        self?.handleResponse(response.response, data: response.data, error: response.error)
      }
    }

//
//    alamofireRequest!.response { [weak self] _, httpResponse, data, error in
//      if let operation = self {
//        operation.handleResponse(httpResponse, data: data, error: error)
//      }
//    }

    status = .running
  }

  open func cancel() {
    alamofireRequest?.cancel()
    status = .cancelled
  }

  open func retry() {
    if status == .cancelled {
      retryCount += 1
      status = .ready
    }
  }

  func buildAlamofireRequest() -> Alamofire.Request {
    return client.alamofireManager.request(request as URLRequest)
  }

  private func handleResponse(_ httpResponse: HTTPURLResponse?, data: Data?, error: Error?) {
    // Store the response and handle it.
    let response = APIResponse(client: client, httpResponse: httpResponse, data: data)
    self.response = response

    if authenticate && response.error?.type == .notAuthorized {

      // Perform an authenticate & retry.
      if retryCount < 3 {
        client.trace("-> Authenticating & retrying")
        client.authenticateAndRetry(self)
      } else {
        client.trace("-> Giving up")
      }
    } else {

      // Call all response handlers.
      DispatchQueue.main.async {
        for handler in self.responseHandlers {
          handler(response)
        }
      }

      // Also resolve the promise.
      if let error = response.error {
        promise.failure(error)
      } else {
        promise.success(response)
      }

      // Call the finally handlers.
      DispatchQueue.main.async {
        for handler in self.finallyHandlers {
          handler()
        }
      }
    }

    alamofireRequest = nil
    completion?()
  }

}

open class APIUpload: APICall {

  override func buildAlamofireRequest() -> Alamofire.Request {
    return Alamofire.SessionManager.default.upload(request.httpBody!, with: request as URLRequest)
  }

}
