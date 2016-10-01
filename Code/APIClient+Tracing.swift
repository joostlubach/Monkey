import Foundation
import SwiftyJSON

extension APIClient {

  func traceRequest(_ request: URLRequest) {
    if traceLevel == .none {
      return
    }

    print("API ---> HTTP \(request.httpMethod!) \(request.url!)")
    if traceLevel == .all {
      if let headers = request.allHTTPHeaderFields {
        for (header, value) in headers {
          print("API      \(header): \(value)")
        }
      }

      if let body = request.httpBody {
        if let bodyString = NSString(data: body, encoding: String.Encoding.utf8.rawValue) {
          print("API      Body: \(bodyString)")
        }
      }
    }
  }

  func traceSuccess(_ status: Int, json: JSON) {
    if traceLevel < .requestsAndStatuses {
      return
    }

    print("API      Success (\(status))")

    if traceLevel == TraceLevel.all && json.type != SwiftyJSON.Type.null {
      print("API      \(json.debugDescription)")
    }
  }

  func traceError(_ error: APIError) {
    if traceLevel < .requestsAndStatuses {
      return
    }

    print("API      \(error)")
  }

  func trace(_ message: String?) {
    if let msg = message {
      print("API      \(msg)")
    }
  }
  
}
