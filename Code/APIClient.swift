import UIKit
import Alamofire
import BrightFutures
import SwiftyJSON

func printToConsole(format: String = "", _ args:[CVarArgType] = [], file: String = #file, function: String = #function, line: Int = #line) {
  print(format)
}

public class APIClient {

  /// Initializes the API client.
  ///
  /// - parameter baseURL:   The base URL for the API. All paths will be appended to this URL.
  public init(baseURL: NSURL, storesSession: Bool = true) {
    self.baseURL = baseURL
    self.storesSession = storesSession
    self.traceHandler = defaultTraceHandler
  }

  /// A delegate for the client.
  public var delegate: APIClientDelegate?

  /// The base URL for the API. All paths will be appended to this URL.
  public let baseURL: NSURL

  /// The Alamofire manager to use for this client.
  public var buildAlamofireManager: (() -> Alamofire.Manager)?

  public var alamofireManager: Alamofire.Manager {
    if let block = buildAlamofireManager {
      return block()
    } else {
      return Alamofire.Manager.sharedInstance
    }
  }

  /// The trace level for this client.
  public var traceLevel: TraceLevel = .RequestsAndStatuses
  
  /// The default trace handler will print to console.
  public let defaultTraceHandler = printToConsole

  /// Set this trace handler so you log, for example, to Crashlytics.
  public var traceHandler: (format: String, args: [CVarArgType], file: String, function: String, line: Int) -> ()!
  
  /// Determines whether the client stores its session in the user defaults.
  public var storesSession: Bool {
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
  public var session: APISession? {
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

      let notificationCenter = NSNotificationCenter.defaultCenter()
      if _session != nil {
        notificationCenter.postNotificationName(Monkey.APIClientDidAuthenticateNotification, object: self)
      } else {
        notificationCenter.postNotificationName(Monkey.APIClientDidUnauthenticateNotification, object: self)
      }
    }
  }

  private func readSessionFromUserDefaults() -> APISession? {
    let userDefaults = NSUserDefaults.standardUserDefaults()

    if let data = userDefaults.dataForKey(SessionKey) {
      return (NSKeyedUnarchiver.unarchiveObjectWithData(data) as! APISession)
    } else {
      return nil
    }
  }

  private func writeSessionToUserDefaults(sessionOrNil: APISession?) {
    let userDefaults = NSUserDefaults.standardUserDefaults()

    if let session = sessionOrNil {
      let data = NSKeyedArchiver.archivedDataWithRootObject(session)
      userDefaults.setObject(data, forKey: SessionKey)
    } else {
      userDefaults.removeObjectForKey(SessionKey)
    }
  }
  


  // MARK: Interface

  public func get(path: String, parameters: [String: AnyObject]? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.GET, path: path, parameters: parameters, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func post(path: String, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.POST, path: path, json: json, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func put(path: String, json: JSON? = nil, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.PUT, path: path, json: json, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func delete(path: String, authenticate: Bool = true) -> APICall {
    let call = buildCallWithMethod(.DELETE, path: path, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  public func upload(path: String, data: NSData, method: Alamofire.Method = .POST, authenticate: Bool = true) -> APICall {
    let call = buildUploadWithMethod(method, path: path, data: data, authenticate: authenticate)
    queue.enqueue(call)
    return call
  }

  // MARK: Authentication

  /// Determines whether the client is currently authenticated.
  public var authenticated: Bool {
    return session != nil && !(session!.expired)
  }

  private var waitingForAuthentication = [APICall]()
  private var authenticationFuture: Future<Void, NoError>?

  /// Checks whether the client has a (non-expired) session, and if not, uses `authenticate()` to authenticate itself.
  public func ensureAuthenticated() -> Future<Bool, NoError> {
    if let session = self.session where !session.expired {
      return Future(value: true)
    } else {
      return authenticate()
    }
  }

  /// Authenticates this client using the authentication handler.
  public func authenticate() -> Future<Bool, NoError> {
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

  private var queue = OperationQueue()

  private func buildMutableURLRequest(method: Alamofire.Method, path: String) -> NSMutableURLRequest {
    let url = baseURL.URLByAppendingPathComponent(path)

    let urlRequest = NSMutableURLRequest(URL: url)
    urlRequest.timeoutInterval = 4
    urlRequest.HTTPMethod = method.rawValue
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

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
    delegate?.client(self, willEnqueueCall: call)
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

private let SessionKey  = "co.mosdev.Monkey-APISession"