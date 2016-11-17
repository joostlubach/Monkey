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
        self.alamofireManager = client.alamofireManager
        self.authenticate = authenticate
        self.request = request
    }
    
    /// The client making the request.
    open unowned let client: APIClient
    
    fileprivate let alamofireManager: Alamofire.SessionManager
    
    open var request: URLRequest
    
    open fileprivate(set) var status = OperationStatus.ready
    
    /// The Alamofire request backing this operation.
    var alamofireRequest: Request?
    
    /// The current try count for this operation.
    open fileprivate(set) var retryCount: Int = 1
    
    /// The response. Only available when the operation is complete.
    open fileprivate(set) var response: APIResponse?
    
    /// Can be set to a block which will receive upload/download progress.
    open var progressBlock: ProgressBlock?
    
    /// A completion block.
    var completion: (() -> Void)?
    
    // MARK: Response handlers
    
    typealias ResponseHandler = (APIResponse) -> Void
    typealias FinallyHandler = () -> Void
    
    fileprivate var responseHandlers = [ResponseHandler]()
    fileprivate var finallyHandlers = [FinallyHandler]()
    
    fileprivate let promise = Promise<APIResponse, APIError>()
    
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
    fileprivate func authenticateRequest() {
        request = (client.session?.authenticateRequest(request))!
    }
    
    // MARK: Start & cancel
    
    open func start() {
        preconditionFailure("This method must be overridden")
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
    
    fileprivate func initStart() {
        if status == .cancelled {
            return
        }
        
        // Authenticate the request if required.
        if authenticate { authenticateRequest() }
        
        alamofireRequest = buildAlamofireRequest()
        
        // Trace this request in the logger.
        client.traceRequest(request)
        
        status = .running
        
    }
    
    // Almofire uses differend kinds of requests now
    fileprivate func buildAlamofireRequest() -> Request {
        preconditionFailure("This method must be overridden")
        //let dataRequest = alamofireManager.request(request)
        //return dataRequest
    }
    
    fileprivate func handleResponse(_ httpResponse: HTTPURLResponse?, data: Data?, error: NSError?) {
        // Store the response and handle it.
        let response = APIResponse(client: client, httpResponse: httpResponse, data: data)
        self.response = response
        
        if authenticate && response.error?.type == .notAuthorized {
            
            // Perform an authenticate & retry.
            if retryCount < 3 {
                client.trace("-> Authenticating & retrying")
                _ = client.authenticateAndRetry(self)
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

// MARK:  Data call
open class APIDataCall: APICall {
    
    
    open override func start() {
        initStart()
        
        // Handle progress.
        (alamofireRequest as! DataRequest).downloadProgress { [weak self] progress in
            self?.progressBlock?(progress.completedUnitCount, progress.totalUnitCount)
            //print("download progress: \(progress.completedUnitCount) of \(progress.totalUnitCount)")
        }
        
        //Handle response
        (alamofireRequest as! DataRequest).response { [weak self] dlResponse in
            
            if let operation = self {
                operation.handleResponse(dlResponse.response, data: dlResponse.data, error: dlResponse.error as NSError?)
            }
        }
    }
    
    
    fileprivate override func buildAlamofireRequest() -> DataRequest {
        let dataRequest = alamofireManager.request(request)
        return dataRequest
    }
}

// MARK: Download call
open class APIDownloadCall: APICall {
    
    open override func start() {
        initStart()
       
        // Handle progress.
        (alamofireRequest as! DownloadRequest).downloadProgress { [weak self] progress in
            self?.progressBlock?(progress.completedUnitCount, progress.totalUnitCount)
        }
        
        //Handle response
        (alamofireRequest as! DownloadRequest).response { [weak self] result in
            
            if let operation = self {
                operation.handleResponse(result.response, data: result.resumeData, error: result.error as NSError?)
            }
        }
    }
    
    
    fileprivate override func buildAlamofireRequest() -> DownloadRequest {
        let downloadRequest = alamofireManager.download(request)
        return downloadRequest
    }
}

// MARK: Upload Call
open class APIUploadCall: APIDataCall {
    
    open override func start() {
        initStart()

        // Handle progress.
        (alamofireRequest as! UploadRequest).uploadProgress { [weak self] progress in
            self?.progressBlock?(progress.completedUnitCount, progress.totalUnitCount)
            //print("upload progress: \(progress.completedUnitCount) of \(progress.totalUnitCount)")

        }
        
        //Handle response
        (alamofireRequest as! UploadRequest).response { [weak self] result in
            if let operation = self {
                operation.handleResponse(result.response, data: result.data, error: result.error as NSError?)
            }
        }
    }
    
    
    fileprivate override func buildAlamofireRequest() -> UploadRequest {
        
        let uploadRequest = alamofireManager.upload(request.httpBody!, with: request)
        return uploadRequest
    }
}
