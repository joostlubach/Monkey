import UIKit

protocol APICredentials {

  func authenticateRequest(request: NSURLRequest) -> NSURLRequest

}

class BearerTokenCredentials: APICredentials {

  init?(token: String) {
    self.token = token
  }

  let token: String

  func authenticateRequest(request: NSURLRequest) -> NSURLRequest {
    let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
    mutableRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return mutableRequest
  }

}

class APIDeviceIdentifierCredentials: BearerTokenCredentials {

  init?() {
    if let identifier = UIDevice.currentDevice().identifierForVendor {
      super.init(token: identifier.UUIDString)
    } else {
      super.init(token: "")
      return nil
    }
  }

}