import UIKit
import Alamofire
import BrightFutures
import Result
import SwiftyJSON

func printToConsole(_ format: String = "", _ args:[CVarArg] = [], file: String = #file, function: String = #function, line: Int = #line) {
    print(format)
}

open class APIClient {
    
    /// Initializes the API client.
    ///
    /// - parameter baseURL:   The base URL for the API. All paths will be appended to this URL.
    public init(baseURL: URL, storesSession: Bool = true) {
        self.baseURL = baseURL
        self.storesSession = storesSession
        self.traceHandler = defaultTraceHandler
    }
    
    /// A delegate for the client.
    open var delegate: APIClientDelegate?
    
    /// The base URL for the API. All paths will be appended to this URL.
    open let baseURL: URL
    
    /// The Alamofire manager to use for this client.
    open var buildAlamofireManager: (() -> Alamofire.SessionManager )?
    
    open var alamofireManager: Alamofire.SessionManager {
        if let block = buildAlamofireManager {
            return block()
        } else {
            return Alamofire.SessionManager.default
        }
    }
    
    /// The trace level for this client.
    open var traceLevel: TraceLevel = .requestsAndStatuses
    
    /// The default trace handler will print to console.
    open let defaultTraceHandler = printToConsole
    
    /// Set this trace handler so you log, for example, to Crashlytics.
    open var traceHandler: (_ format: String, _ args: [CVarArg], _ file: String, _ function: String, _ line: Int) -> ()!
    
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
    
    fileprivate var _session: APISession?
    
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
                notificationCenter.post(name: Notification.Name(rawValue: Monkey.APIClientDidAuthenticateNotification), object: self)
            } else {
                notificationCenter.post(name: Notification.Name(rawValue: Monkey.APIClientDidUnauthenticateNotification), object: self)
            }
        }
    }
    
    fileprivate func readSessionFromUserDefaults() -> APISession? {
        let userDefaults = UserDefaults.standard
        
        if let data = userDefaults.data(forKey: SessionKey) {
            return (NSKeyedUnarchiver.unarchiveObject(with: data) as! APISession)
        } else {
            return nil
        }
    }
    
    fileprivate func writeSessionToUserDefaults(_ sessionOrNil: APISession?) {
        let userDefaults = UserDefaults.standard
        
        if let session = sessionOrNil {
            let data = NSKeyedArchiver.archivedData(withRootObject: session)
            userDefaults.set(data, forKey: SessionKey)
        } else {
            userDefaults.removeObject(forKey: SessionKey)
        }
    }
    
    
    
    // MARK: Interface
    
    // DataRequest (defaults to get)
    open func get(_ path: String, parameters: [String: Any]? = nil, authenticate: Bool = true) -> APIDataCall {
        //print("APICLient get: \(path)")  // for debugging
        let call = buildDataCallWithMethod(.get, path: path, parameters: parameters, authenticate: authenticate)
        queue.enqueue(call)
        return call
    }
    
    // upload with urlstring (defaults to post)
    open func post(_ path: String, json: JSON? = nil, authenticate: Bool = true) -> APIDataCall {
        //print("APICLient post: \(path)") // for debugging
        let call = buildDataCallWithMethod(.post, path: path, json: json, authenticate: authenticate)
        queue.enqueue(call)
        return call
    }
    
    // upload method: .put
    open func put(_ path: String, json: JSON? = nil, authenticate: Bool = true) -> APIDataCall {
        //print("APICLient put: \(path)")  // for debugging
        let call = buildDataCallWithMethod(.put, path: path, json: json, authenticate: authenticate)
        queue.enqueue(call)
        return call
    }
    // DataRequest method: .delete
    open func delete(_ path: String, authenticate: Bool = true) -> APIDataCall {
        let call = buildDataCallWithMethod(.delete, path: path, authenticate: authenticate)
        queue.enqueue(call)
        return call
    }
    
    // direct upload
    open func upload(_ path: String, data: Data, method: Alamofire.HTTPMethod = .post, authenticate: Bool = true) -> APIUploadCall {
        let call = buildUploadCallWithMethod(method, path: path, data: data, authenticate: authenticate)
        queue.enqueue(call)
        return call
        
    }
    
    // MARK: Authentication
    
    /// Determines whether the client is currently authenticated.
    open var authenticated: Bool {
        return session != nil && !(session!.expired)
    }
    
    fileprivate var waitingForAuthentication = [APICall]()
    fileprivate var authenticationFuture: Future<Void, NoError>?
    
    /// Checks whether the client has a (non-expired) session, and if not, uses `authenticate()` to authenticate itself.
    open func ensureAuthenticated() -> Future<Bool, NoError> {
        if let session = self.session , !session.expired {
            return Future(value: true)
        } else {
            return authenticate()
        }
    }
    
    /// Authenticates this client using the authentication handler.
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
    
    fileprivate var queue = OperationQueue()
    
    fileprivate func buildURLRequest(_ method: Alamofire.HTTPMethod, path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        
        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 4
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return urlRequest
    }
    
    fileprivate func buildDataCallWithMethod(_ method: Alamofire.HTTPMethod, path: String, parameters: [String: Any]? = nil, json: JSON? = nil, authenticate: Bool = true) -> APIDataCall {
        var urlRequest = buildURLRequest(method, path: path)
        //print(urlRequest.debugDescription)  // Debug
        // Use Alamofire's parameter encoding to encode the parameters.
        if let params = parameters {
            do {
              urlRequest = try URLEncoding.default.encode(urlRequest, with: params)
            } catch {
                print ("error in URLencoding")
            }
            
        } else if let js = json {
            do {
                urlRequest = try JSONEncoding.default.encode(urlRequest, with: js.dictionaryObject)
            } catch {
                print ("error in JSONencoding")
            }
        }
        
        let call = APIDataCall(client: self, request: urlRequest, authenticate: authenticate)
        prepareCall(call)
        return call
    }
    
    
    fileprivate func buildDownloadCallWithMethod(_ method: Alamofire.HTTPMethod, path: String, data: Data, authenticate: Bool = true) -> APIDownloadCall {
        let request = buildURLRequest(method, path: path)
        
        let call = APIDownloadCall(client: self, request: request, authenticate: authenticate)
      
        prepareCall(call)
        return call
    }
    
    fileprivate func buildUploadCallWithMethod(_ method: Alamofire.HTTPMethod, path: String, data: Data, authenticate: Bool = true) -> APIUploadCall {
        var request = buildURLRequest(method, path: path)
        //print("uploading: \(request)") // for debugging
        request.httpBody = data
        request.timeoutInterval = 30
        
        let call = APIUploadCall(client: self, request: request, authenticate: authenticate)
        prepareCall(call)
        return call
    }
    
    fileprivate func prepareCall(_ call: APICall) {
        addDefaultHandlers(call)
        delegate?.client(self, willEnqueueCall: call)
    }
    
    fileprivate func addDefaultHandlers(_ call: APICall) {
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
