import Foundation
import BrightFutures

public protocol APIClientDelegate: class {

  /// A handler for authentication. This is called either when `authenticate()` is called (or when `ensureAuthenticated()` is called
  /// and the client does not have a session, or when any API (authenticated) request encounters a 401 Not Authorized error.
  ///
  /// This handler is supposed to return a future with an API session. The future may fail if the authentication fails. This failure
  /// is logged, but not displayed to the user.
  ///
  /// In case any error occurs, you should handle this and return a successful future with a nil argument.
  func authenticateClient(client: APIClient) -> Future<Void, NoError>

  /// Called when the client will enqueue a call. Use this to add default headers, behavior or error handling.
  func client(client: APIClient, willEnqueueCall call: APICall)

}

// MARK: - Default implementations

public extension APIClientDelegate {

  func authenticateClient(client: APIClient) -> Future<Void, NoError> {
    return Future(value: ())
  }

  func client(client: APIClient, willEnqueueCall call: APICall) {}

}