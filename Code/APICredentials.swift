import UIKit

protocol APICredentials {

  func authenticateRequest(_ request: URLRequest) -> URLRequest

}

class BearerTokenCredentials: APICredentials {

  init?(token: String) {
    self.token = token
  }

  let token: String

  func authenticateRequest(_ request: URLRequest) -> URLRequest {
    let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
    mutableRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return mutableRequest as URLRequest
  }

}

class APIDeviceIdentifierCredentials: BearerTokenCredentials {

  init?() {
    if let identifier = UIDevice.current.identifierForVendor {
      super.init(token: identifier.uuidString)
    } else {
      super.init(token: "")
      return nil
    }
  }

}
