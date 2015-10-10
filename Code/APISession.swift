import Foundation

public protocol APISession: NSCoding {

  var expired: Bool { get }
  func authenticateRequest(request: NSMutableURLRequest)

}

public class BearerTokenAPISession: NSObject, APISession, NSCoding {

  public init(token: String, expirationDate: NSDate? = nil) {
    self.token = token
    self.expirationDate = expirationDate
  }
  required convenience public init?(coder: NSCoder) {
    let token = coder.decodeObjectForKey("token") as! String
    let expirationDate = coder.decodeObjectForKey("expirationDate") as! NSDate?

    self.init(token: token, expirationDate: expirationDate)
  }

  public func encodeWithCoder(coder: NSCoder) {
    coder.encodeObject(token, forKey: "token")
    coder.encodeObject(expirationDate, forKey: "expirationDate")
  }

  let token: String
  let expirationDate: NSDate?

  public var expired: Bool {
    if let date = expirationDate where date.compare(NSDate()) == .OrderedAscending {
      return true
    } else {
      return false
    }
  }

  public var authorizationHeader: String {
    return "Bearer \(token)"
  }

  public func authenticateRequest(request: NSMutableURLRequest) {
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
  }

}