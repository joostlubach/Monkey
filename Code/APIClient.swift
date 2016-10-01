import UIKit
import Alamofire
import BrightFutures
import SwiftyJSON
import Result

open class APIClient {

  /// Initializes the API client.
  ///
  /// - parameter baseURL:   The base URL for the API. All paths will be appended to this URL.
  public init(baseURL: URL, storesSession: Bool = true) {
    self.baseURL = baseURL
    self.storesSession = storesSession
  }

  /// A delegate for the client.
  open var delegate: APIClientDelegate?

  /// The base URL for the API. All paths will be appended to this URL.
  open let baseURL: URL

  /// The Alamofire manager to use for this client.
  open var alamofireManager = Alamofire.SessionManager.default

  /// The trace level for this client.
  open var traceLevel: TraceLevel = .requestsAndStatuses

  /// Determines whether the client stores its session in the user defaults.
  open var storesSession: Bool {
    didSet {
      if storesSession {
        writeSessionToUserDefaults(session)
      } else {
        writeSessionToUserDefaults(nil)
      }
    }
  }

  private var _session: APISession?

  /// An API session. This may store some token so that the API is authenticated.
  open var session: APISession? {
    get {
      if _session == nil && storesSession {
        _session = readSessionFromUserDefaults()
      }
      return _session
    }
    set {
      if _session === newValue {
        return
      }

      _session = newValue

      if storesSession {
        writeSessionToUserDefaults(_session)
      }

      let notificationCenter = NotificationCenter.default
      if _session != nil {
        notificationCenter.post(name: Monkey.APIClientDidAuthenticateNotification, object: self)
      } else {
        notificationCenter.post(name: Monkey.APIClientDidUnauthenticateNotification, object: self)
      }
    }
  }

  private func readSessionFromUserDefaults() -> APISession? {
    let userDefaults = UserDefaults.standard

    if let data = userDefaults.data(forKey: SessionKey) {
      return (NSKeyedUnarchiver.unarchiveObject(with: data) as! APISession)
    } else {
      return nil
    }
  }

  private func writeSessionToUserDefaults(_ sessionOrNil: APISession?) {
    let userDefaults = UserDefaults.standard

    if let session = sessionOrNil {
      let data = NSKeyedArchiver.archivedData(withRootObject: session)
      userDefaults.set(data, forKey: SessionKey)
    } else {
      userDefaults.removeObject(forKey: SessionKey)
    }
  }
  


  // MARK: Interface

  @discardableResult
  open func get(_ path: String, parameters: [String: Any]? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.get, path: path, parameters: parameters, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  @discardableResult
  open func post(_ path: String, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.post, path: path, json: json, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  @discardableResult
  open func put(_ path: String, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.put, path: path, json: json, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  @discardableResult
  open func delete(_ path: String, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.delete, path: path, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  @discardableResult
  open func upload(_ path: String, data: Data, method: Alamofire.HTTPMethod = .post, authenticate: Bool = true) -> APICall {
    let call = buildUploadWithMethod(method, path: path, data: data, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  // MARK: Authentication

  /// Determines whether the client is currently authenticated.
  open var authenticated: Bool {
    return session != nil && !(session!.expired)
  }

  private var waitingForAuthentication = [APICall]()
  private var authenticationFuture: Future<Void, NoError>?

  /// Checks whether the client has a (non-expired) session, and if not, uses `authenticate()` to authenticate itself.
  open func ensureAuthenticated() -> Future<Bool, NoError> {
    if let session = self.session , !session.expired {
      return Future(value: true)
    } else {
      return authenticate()
    }
  }

  /// Authenticates this client using the authentication handler.
  @discardableResult
  open func authenticate() -> Future<Bool, NoError> {
    if let delegate = delegate {
      return delegate.authenticateClient(self).map { _ in
        // We have successfully authenticated if the handler has set the session object.
        self.session != nil
      }
    } else {
      return Future(value: false)
    }
  }

  /// Authenticates the client and retries the given operation. The operation is stalled while authentication is performed.
  @discardableResult
  final func authenticateAndRetry(_ operation: APICall) -> Future<Void, NoError> {
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

  private var queue = OperationQueue()

  private func buildMutableURLRequest(_ method: Alamofire.HTTPMethod, path: String) -> MutableURLRequest {
    let url = baseURL.appendingPathComponent(path)

    let urlRequest = NSMutableURLRequest(url: url)
    urlRequest.timeoutInterval = 4
    urlRequest.httpMethod = method.rawValue
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    return urlRequest
  }

  private func buildCallWithMethod(_ method: Alamofire.HTTPMethod, path: String, parameters: [String: Any]? = nil, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    var request = buildMutableURLRequest(method, path: path)

    // Use Alamofire's parameter encoding to encode the parameters.
    if let params = parameters, let encodedRequest = try? URLEncoding.default.encode(request as URLRequest, with: params) {
      request = (encodedRequest as NSURLRequest).mutableCopy() as! MutableURLRequest
    } else if let js = json, let encodedRequest = try? JSONEncoding.default.encode(request as URLRequest, with: js.dictionaryObject) {
      request = (encodedRequest as NSURLRequest).mutableCopy() as! MutableURLRequest
    }

    let call = APICall(client: self, request: request, authenticate: authenticate)
    prepareCall(call)
    return call
  }

  private func buildUploadWithMethod(_ method: Alamofire.HTTPMethod, path: String, data: Data, authenticate: Bool = true) -> APIUpload {
    let request = buildMutableURLRequest(method, path: path)
    request.httpBody = data

    let call = APIUpload(client: self, request: request, authenticate: authenticate)
    prepareCall(call)
    return call
  }

  private func prepareCall(_ call: APICall) {
    addDefaultHandlers(call)
    delegate?.client(self, willEnqueueCall: call)
  }

  private func addDefaultHandlers(_ call: APICall) {
    // Show/hide network activity indicator.
    UIApplication.shared.isNetworkActivityIndicatorVisible = true
    call.response { [weak self] _ in
      if let client = self , client.queue.count == 0 {
        // This is the last operation, and it's complete.
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
      }
    }
  }

}

private let SessionKey  = "co.mosdev.Monkey-APISession"
