import Foundation
import SwiftyJSON

extension APIClient {
  
  func traceRequest(request: NSURLRequest) {
    if traceLevel == .None {
      return
    }

    trace("API ---> HTTP \(request.HTTPMethod!) \(request.URL!)")
    if traceLevel == .All {
      if let headers = request.allHTTPHeaderFields {
        for (header, value) in headers {
          trace("API      \(header): \(value)")
        }
      }

      if let body = request.HTTPBody {
        if let bodyString = NSString(data: body, encoding: NSUTF8StringEncoding) {
          trace("API      Body: \(bodyString)")
        }
      }
    }
  }

  func traceSuccess(status: Int, json: JSON) {
    if traceLevel < .RequestsAndStatuses {
      return
    }

    trace("API      Success (\(status))")

    if traceLevel == .All && json.type != .Null {
      trace("API      \(json.debugDescription)")
    }
  } 

  func traceError(error: APIError) {
    if traceLevel < .RequestsAndStatuses {
      return
    }

    trace("API      \(error)")
  }

  func trace(message: String?) {
    if let msg = message {
      self.traceHandler(format: msg, args: [], file: "APIClient", function: "?", line: 0)
    }
  }
  
}
