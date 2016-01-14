import Foundation
import SwiftyJSON

public class APIResponse {

  init(client: APIClient?, httpResponse: NSHTTPURLResponse?, data: NSData?) {
    self.client = client
    self.httpResponse = httpResponse
    self.data = data

    resolve()
  }

  public weak var client: APIClient?
  public let httpResponse: NSHTTPURLResponse?

  public private(set) var status = 0
  public private(set) var error: APIError?
  public private(set) var underlyingError: NSError?

  var success: Bool {
    return error == nil
  }

  public private(set) var data: NSData?
  public private(set) var json: JSON?

  // MARK: Handlers

  public func whenSuccess(@noescape block: (APIResponse) -> Void) {
    if success {
      block(self)
    }
  }

  public func whenData(@noescape block: (NSData) -> Void) {
    if let data = data {
      block(data)
    }
  }

  public func whenJSON(@noescape block: (JSON) -> Void) {
    if let json = json {
      block(json)
    }
  }

  public func whenError(@noescape block: (APIError) -> Void) {
    if let error = error {
      block(error)
    }
  }

  public func whenErrorOfType(errorType: APIErrorType, @noescape block: (APIError) -> Void) {
    if let error = error where error.type == errorType {
      block(error)
    }
  }

  // MARK: Resolution

  func resolve() {
    status = httpResponse?.statusCode ?? 0

    if let data = self.data where data.length > 0 {
      do {
        let jsonDict: AnyObject = try NSJSONSerialization.JSONObjectWithData(data, options: [])
        json = JSON(jsonDict)
      } catch let error as NSError {
        json = nil

        // Mark an invalid data error. This might be overridden later if there is a specific HTTP error.
        self.error = APIError(type: .InvalidData)
        self.error!.underlyingError = error
      }
    }

    // Handle HTTP specific errors.
    switch status {
    case 0: handleError(.NotReachable)
    case 100..<400: handleSuccess() // Might still be a server error.
    case 400: handleError(.BadRequest)
    case 401: handleError(.NotAuthorized)
    case 403: handleError(.Forbidden)
    case 404: handleError(.NotFound)
    case 400..<500: handleError(.OtherClientError)
    default: handleServerError()
    }

    if let error = error {
      client?.traceError(error)
    }
  }

  private func handleSuccess() {
    client?.traceSuccess(status, json: json ?? JSON.null)
  }

  private func handleError(errorType: APIErrorType) {
    let message = json?["error"].string
    error = APIError(type: errorType, status: status, message: message)
  }

  private func handleServerError() {
    let message = json?["error"].string
    error = APIError(type: .ServerError, status: status, message: message)

    // Dump the full server data.
    if let data = self.data, let output = NSString(data: data, encoding: NSUTF8StringEncoding) {
      print("---- SERVER OUTPUT ----")
      print(output)
      print("---- END OF SERVER OUTPUT ----")
    }
  }

}