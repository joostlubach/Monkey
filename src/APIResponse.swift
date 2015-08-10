import Foundation
import SwiftyJSON

public class APIResponse {

  public enum ResponseType {
    case Success
    case NotReachable
    case NotAuthorized
    case ClientError
    case ServerError
  }

  init(client: APIClient, httpResponse: NSHTTPURLResponse?, data: NSData?) {
    self.client = client
    self.httpResponse = httpResponse
    self.data = data

    resolve()
  }

  public weak var client: APIClient?
  public let httpResponse: NSHTTPURLResponse?

  public private(set) var type   = ResponseType.NotReachable
  public private(set) var status = 0
  
  public private(set) var data: NSData?
  public private(set) var json: JSON?

  public private(set) var error: NSError?

  // MARK: Handlers

  public func whenData(@noescape block: (NSData) -> Void) {
    if let data = self.data {
      block(data)
    }
  }

  public func whenJSON(@noescape block: (JSON) -> Void) {
    if let json = self.json {
      block(json)
    } else {
      fatalError("Cannot read JSON (may be malformed?)")
    }
  }

  // MARK: Resolution

  func resolve() {
    status = httpResponse?.statusCode ?? 0

    if let data = self.data {
      if let jsonDict: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: nil, error: nil) {
        json = JSON(jsonDict)
      }
    }

    // Handle HTTP specific errors.
    switch status {
    case 0: handleConnectionError()
    case 100..<400: handleSuccess() // Might still be a server error.
    case 401: handleNotAuthorized()
    case 400..<500: handleClientError()
    default: handleServerError()
    }

    if status < 100 || status >= 400 {
      error = NSError(domain: Monkey.ErrorDomain, code: Monkey.ErrorCodes.HTTPError.rawValue, userInfo: ["HTTPStatus": status])
    } else {
      error = nil
    }
  }

  private func handleSuccess() {
    if let error = json?["error"].string {
      type = .ServerError
      client?.traceError(status, message: "Server error: \(error)")
    } else {
      type = .Success
      client?.traceSuccess(status, json: json ?? JSON.nullJSON)
    }
  }

  private func handleConnectionError() {
    type = .NotReachable
    client?.traceError(status, message: "Could not connect")
  }

  private func handleNotAuthorized() {
    type = .NotAuthorized
    client?.traceError(status, message: jsonError(defaultError: "Not Authorized"))
  }

  private func handleClientError() {
    type = .ClientError
    client?.traceError(status, message: jsonError(defaultError: "Client error"))

    // A client error is a programming error in the app. Always abort.
    abort()
  }

  private func handleServerError() {
    type = .ServerError
    client?.traceError(status, message: "Server error")

    if let data = self.data, let output = NSString(data: data, encoding: NSUTF8StringEncoding) {
      // Just dump the data to the log.
      println("---- SERVER OUTPUT ----")
      println(output)
      println("---- END OF SERVER OUTPUT ----")
    }
  }

  private func jsonError(#defaultError: String) -> String {
    if let error = json?["error"].string {
      return error
    } else {
      return defaultError
    }
  }

}