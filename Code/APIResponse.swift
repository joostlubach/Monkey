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
  public private(set) var underlyingErrorMessage: String?

  var success: Bool {
    return error == nil
  }

  public private(set) var data: NSData?
  public private(set) var json: JSON?

  // MARK: Handlers

  public func whenData(@noescape block: (NSData) -> Void) {
    if let data = self.data {
      block(data)
    }
  }

  public func whenJSON(@noescape block: (JSON) -> Void) {
    if let json = self.json {
      block(json)
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
        self.error = .InvalidData
        underlyingError = error
        underlyingErrorMessage = error.localizedDescription
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
  }

  private func handleSuccess() {
    client?.traceSuccess(status, json: json ?? JSON.null)
  }

  private func handleError(error: APIError) {
    self.error = error
    underlyingErrorMessage = json?["error"].string
    client?.traceError(status, message: underlyingErrorMessage ?? error.description)
  }

  private func handleServerError() {
    error = .ServerError
    underlyingErrorMessage = json?["error"].string
    client?.traceError(status, message: underlyingErrorMessage ?? error!.description)

    // Dump the full server data.
    if let data = self.data, let output = NSString(data: data, encoding: NSUTF8StringEncoding) {
      print("---- SERVER OUTPUT ----")
      print(output)
      print("---- END OF SERVER OUTPUT ----")
    }
  }

}