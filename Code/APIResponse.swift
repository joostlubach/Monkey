import Foundation
import SwiftyJSON

open class APIResponse {

  init(client: APIClient?, httpResponse: HTTPURLResponse?, data: Data?) {
    self.client = client
    self.httpResponse = httpResponse
    self.data = data

    resolve()
  }

  open weak var client: APIClient?
  open let httpResponse: HTTPURLResponse?

  open private(set) var status = 0
  open private(set) var error: APIError?
  open private(set) var underlyingError: NSError?

  var success: Bool {
    return error == nil
  }

  open private(set) var data: Data?
  open private(set) var json: JSON?

  // MARK: Handlers

  open func whenSuccess(_ block: (APIResponse) -> Void) {
    if success {
      block(self)
    }
  }

  open func whenData(_ block: (Data) -> Void) {
    if let data = data {
      block(data)
    }
  }

  open func whenJSON(_ block: (JSON) -> Void) {
    if let json = json {
      block(json)
    }
  }

  open func whenError(_ block: (APIError) -> Void) {
    if let error = error {
      block(error)
    }
  }

  open func whenErrorOfType(_ errorType: APIErrorType, block: (APIError) -> Void) {
    if let error = error , error.type == errorType {
      block(error)
    }
  }

  // MARK: Resolution

  func resolve() {
    status = httpResponse?.statusCode ?? 0

    if let data = self.data , data.count > 0 {
      do {
        let jsonDict = try JSONSerialization.jsonObject(with: data, options: [])
        json = JSON(jsonDict)
      } catch let error as NSError {
        json = nil

        // Mark an invalid data error. This might be overridden later if there is a specific HTTP error.
        self.error = APIError(type: .invalidData)
        self.error!.underlyingError = error
      }
    }

    // Handle HTTP specific errors.
    switch status {
    case 0: handleError(.notReachable)
    case 100..<400: handleSuccess() // Might still be a server error.
    case 400: handleError(.badRequest)
    case 401: handleError(.notAuthorized)
    case 403: handleError(.forbidden)
    case 404: handleError(.notFound)
    case 400..<500: handleError(.otherClientError)
    default: handleServerError()
    }

    if let error = error {
      client?.traceError(error)
    }
  }

  private func handleSuccess() {
    client?.traceSuccess(status, json: json ?? JSON.null)
  }

  private func handleError(_ errorType: APIErrorType) {
    let message = json?["error"].string
    error = APIError(type: errorType, status: status, message: message)
    error!.json = json
    error!.data = data
  }

  private func handleServerError() {
    let message = json?["error"].string
    error = APIError(type: .ServerError, status: status, message: message)
    error!.json = json
    error!.data = data

    // Dump the full server data.
    if let data = self.data, let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
      print("---- SERVER OUTPUT ----")
      print(output)
      print("---- END OF SERVER OUTPUT ----")
    }
  }

}
