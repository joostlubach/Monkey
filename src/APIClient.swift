import UIKit
import Alamofire
import BrightFutures
import SwiftyJSON

public class APIClient {

  /**
  Initializes the API client.

  :param: baseURL   The base URL for the API. All paths will be appended to this URL.
  */
  public init(baseURL: NSURL, storesSession: Bool = true) {
    self.baseURL = baseURL
    self.storesSession = storesSession
  }

  /// The base URL for the API. All paths will be appended to this URL.
  public let baseURL: NSURL

  /// Determines whether the client stores its session in the user defaults.
  public var storesSession: Bool {
    didSet {
      if storesSession {
        Monkey.writeSessionToUserDefaults(session)
      } else {
        Monkey.writeSessionToUserDefaults(nil)
      }
    }
  }

  private var _session: APISession?

  /// An API session. This may store some token so that the API is authenticated.
  public var session: APISession? {
    get {
      if _session == nil && storesSession {
        _session = Monkey.readSessionFromUserDefaults()
      }
      return _session
    }
    set {
      if _session === newValue {
        return
      }

      _session = newValue

      if storesSession {
        Monkey.writeSessionToUserDefaults(_session)
      }

      let notificationCenter = NSNotificationCenter.defaultCenter()
      if _session != nil {
        notificationCenter.postNotificationName(Monkey.APIClientDidAuthenticateNotification, object: self)
      } else {
        notificationCenter.postNotificationName(Monkey.APIClientDidUnauthenticateNotification, object: self)
      }
    }
  }

  // MARK: Interface

  public func get(path: String, parameters: [String: AnyObject]? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.GET, path: path, parameters: parameters, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func post(path: String, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    var call = buildCallWithMethod(.POST, path: path, json: json, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func put(path: String, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    var call = buildCallWithMethod(.PUT, path: path, json: json, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func delete(path: String, authenticate: Bool = true) -> APICall {
    var call = buildCallWithMethod(.DELETE, path: path, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func upload(path: String, data: NSData, method: Alamofire.Method = .POST, authenticate: Bool = true) -> APICall {
    let call = buildUploadWithMethod(method, path: path, data: data, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  // MARK: Authentication

  /// A handler for authentication. This is called either when `authenticate()` is called (or when `ensureAuthenticated()` is called
  /// and the client does not have a session, or when any API (authenticated) request encounters a 401.
  ///
  /// This handler is supposed to return a future with an API session. The future may fail if the authentication fails. This failure
  /// is logged, but not displayed to the user.
  ///
  /// In case any error occurs, you should handle this and return a successful future with a nil argument.
  public var authenticationHandler: ((APIClient) -> Future<Void, NoError>)?

  /// Determines whether the client is currently authenticated.
  public var authenticated: Bool {
    return session != nil && !(session!.expired)
  }

  private var waitingForAuthentication = [APICall]()
  private var authenticationFuture: Future<Void, NoError>?

  /// Checks whether the client has a (non-expired) session, and if not, uses `authenticate()` to authenticate itself.
  public func ensureAuthenticated() -> Future<Bool, NoError> {
    if let session = self.session where !session.expired {
      return Future.succeeded(true)
    } else {
      return authenticate()
    }
  }

  /// Authenticates this client using the authentication handler.
  public func authenticate() -> Future<Bool, NoError> {
    if let block = authenticationHandler {
      return block(self).map {
        return self.session != nil
      }
    } else {
      // Pretend to have been authenticated.
      self.session = nil
      return Future.succeeded(false)
    }
  }

  /// Authenticates the client and retries the given operation. The operation is stalled while authentication is performed.
  final func authenticateAndRetry(operation: APICall) -> Future<Void, NoError> {
    // Cancel this operation.
    operation.cancel()

    // Add it to a list of operations to be re-executed upon authentication.
    waitingForAuthentication.append(operation)

    // If there is already an authentication process going on, hook into it.
    if let future = authenticationFuture {
      return future
    }

    // Perform authentication.
    let authFuture = authenticate()

    // After the authentication succeeded, requeue all pending operations. If it fails, log the exact reason,
    // but just return false so that the operations waiting on authentication can all fail with a 401.
    authenticationFuture = authFuture.map { authenticated in
      // If the user cancelled, or the authentication failed in some way, don't retry.
      if authenticated {
        for call in self.waitingForAuthentication {
          call.retry()
          self.queue.enqueue(call)
        }
      } else {
        for call in self.waitingForAuthentication {
          call.cancel()
        }
      }
      self.waitingForAuthentication = []
      self.authenticationFuture = nil
    }

    return authenticationFuture!
  }

  // MARK: Requests

  public typealias PreparationBlock = (APICall) -> Void

  private var preparationBlocks = [PreparationBlock]()

  private var queue = OperationQueue()

  /**
  Adds a handler to be executed on all requests.

  Example
    The following example adds a default failure response:

      client.prepare { call in
        call.responseError { error in
          displayError(error)
        }
      }
  */
  public func prepare(block: PreparationBlock) {
    preparationBlocks.append(block)
  }

  private func buildMutableURLRequest(method: Alamofire.Method, path: String) -> NSMutableURLRequest {
    let url = baseURL.URLByAppendingPathComponent(path)

    let urlRequest = NSMutableURLRequest(URL: url)
    urlRequest.timeoutInterval = 4
    urlRequest.HTTPMethod = method.rawValue

    return urlRequest
  }

  private func buildCallWithMethod(method: Alamofire.Method, path: String, parameters: [String: AnyObject]? = nil, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    var request = buildMutableURLRequest(method, path: path)

    // Use Alamofire's parameter encoding to encode the parameters.
    if let params = parameters {
      request = ParameterEncoding.URL.encode(request, parameters: params).0.mutableCopy() as! NSMutableURLRequest
    } else if let js = json {
      request = ParameterEncoding.JSON.encode(request, parameters: js.dictionaryObject).0.mutableCopy() as! NSMutableURLRequest
    }

    let call = APICall(client: self, request: request, authenticate: authenticate)
    prepareCall(call)
    return call
  }

  private func buildUploadWithMethod(method: Alamofire.Method, path: String, data: NSData, authenticate: Bool = true) -> APIUpload {
    let request = buildMutableURLRequest(method, path: path)
    request.HTTPBody = data

    let call = APIUpload(client: self, request: request, authenticate: authenticate)
    prepareCall(call)
    return call
  }

  private func prepareCall(call: APICall) {
    addDefaultHandlers(call)

    for block in preparationBlocks {
      block(call)
    }
  }

  private func addDefaultHandlers(call: APICall) {
    // Show/hide network activity indicator.
    UIApplication.sharedApplication().networkActivityIndicatorVisible = true
    call.response { [weak self] _ in
      if let client = self where client.queue.count == 0 {
        // This is the last operation, and it's complete.
        UIApplication.sharedApplication().networkActivityIndicatorVisible = false
      }
    }
  }

}