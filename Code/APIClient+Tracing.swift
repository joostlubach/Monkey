import Foundation
import SwiftyJSON

extension APIClient {
  
  func traceRequest(_ request: URLRequest) {
    if traceLevel == .none {
      return
    }

    trace("API ---> HTTP \(request.httpMethod!) \(request.url!)")
    if traceLevel == .all {
      if let headers = request.allHTTPHeaderFields {
        for (header, value) in headers {
          trace("API      \(header): \(value)")
        }
      }

      if let body = request.httpBody {
        if let bodyString = NSString(data: body, encoding: String.Encoding.utf8.rawValue) {
          trace("API      Body: \(bodyString)")
        }
      }
    }
  }

  func traceSuccess(_ status: Int, json: JSON) {
    if traceLevel < .requestsAndStatuses {
      return
    }

    trace("API      Success (\(status))")

    if traceLevel == .all && json.type != .null {
      var msg = json.debugDescription
      
      if let array = json.array {
        if array.count == 0 {
          msg = "[]" // Empty arrays screwed up logging for some reason
        }
      }
      trace("API      JSON = \(msg)")
    }
  } 

  func traceError(_ error: APIError) {
    if traceLevel < .requestsAndStatuses {
      return
    }

    trace("API      Error, JSON = \(error)")
  }

  func trace(_ message: String?) {
    if let msg = message {
      self.traceHandler(msg, [], "APIClient", "?", 0)
    }
  }
  
}
