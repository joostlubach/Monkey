import Foundation
import SwiftyJSON

extension APIClient {

  func traceRequest(request: NSURLRequest) {
    if traceLevel == .None {
      return
    }

    print("API ---> HTTP \(request.HTTPMethod!) \(request.URL!)")
    if traceLevel == .All {
      if let headers = request.allHTTPHeaderFields {
        for (header, value) in headers {
          print("API      \(header): \(value)")
        }
      }

      if let body = request.HTTPBody {
        if let bodyString = NSString(data: body, encoding: NSUTF8StringEncoding) {
          print("API      Body: \(bodyString)")
        }
      }
    }
  }

  func traceSuccess(status: Int, json: JSON) {
    if traceLevel < .RequestsAndStatuses {
      return
    }

    print("API      Success (\(status))")

    if traceLevel == .All && json.type != .Null {
      print("API      \(json.debugDescription)")
    }
  }

  func traceError(error: APIError) {
    if traceLevel < .RequestsAndStatuses {
      return
    }

    print("API      \(error)")
  }

  func trace(message: String?) {
    if let msg = message {
      print("API      \(msg)")
    }
  }
  
}
