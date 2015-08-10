import Foundation
import SwiftyJSON

extension APIClient {

  func traceRequest(request: NSURLRequest) {
    if Monkey.traceLevel == .None {
      return
    }

    println("API ---> HTTP \(request.HTTPMethod!) \(request.URL!)")
    if Monkey.traceLevel == .All {
      if let headers = request.allHTTPHeaderFields {
        for (header, value) in headers {
          println("API      \(header): \(value)")
        }
      }

      if let body = request.HTTPBody {
        if let bodyString = NSString(data: body, encoding: NSUTF8StringEncoding) {
          println("API      Body: \(bodyString)")
        }
      }
    }
  }

  func traceSuccess(status: Int, json: JSON) {
    if Monkey.traceLevel.lowerThan(.RequestsAndStatuses) {
      return
    }

    println("API      Success (\(status))")

    if Monkey.traceLevel == .All && json.type != .Null {
      println("API      \(json.debugDescription)")
    }
  }

  func traceError(status: Int, message: String?) {
    if Monkey.traceLevel.lowerThan(.RequestsAndStatuses) {
      return
    }

    if let msg = message {
      println("API      Error (\(status)) \(msg)")
    } else {
      println("API      Error (\(status))")
    }
  }

  func trace(message: String?) {
    if let msg = message {
      println("API      \(msg)")
    }
  }
  
}
