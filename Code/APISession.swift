import Foundation

public protocol APISession: NSCoding {

  var expired: Bool { get }
  func authenticateRequest(_ request: NSMutableURLRequest)

}

open class BearerTokenAPISession: NSObject, APISession, NSCoding {

  public init(token: String, expirationDate: Date? = nil) {
    self.token = token
    self.expirationDate = expirationDate
  }
  required convenience public init?(coder: NSCoder) {
    let token = coder.decodeObject(forKey: "token") as! String
    let expirationDate = coder.decodeObject(forKey: "expirationDate") as! Date?

    self.init(token: token, expirationDate: expirationDate)
  }

  open func encode(with coder: NSCoder) {
    coder.encode(token, forKey: "token")
    coder.encode(expirationDate, forKey: "expirationDate")
  }

  let token: String
  let expirationDate: Date?

  open var expired: Bool {
    if let date = expirationDate , date.compare(Date()) == .orderedAscending {
      return true
    } else {
      return false
    }
  }

  open var authorizationHeader: String {
    return "Bearer \(token)"
  }

  open func authenticateRequest(_ request: NSMutableURLRequest) {
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
  }

}
