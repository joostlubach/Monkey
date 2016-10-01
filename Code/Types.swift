import Foundation

public let APIClientDidAuthenticateNotification = "co.mosdev.Monkey.APIClientDidAuthenticate"
public let APIClientDidUnauthenticateNotification = "co.mosdev.Monkey.APIClientDidAuthenticate"

public enum TraceLevel: Int {
  case none                = 0
  case requestsOnly        = 1
  case requestsAndStatuses = 2
  case all                 = 10
}

extension TraceLevel: Comparable {}

public func <(lhs: TraceLevel, rhs: TraceLevel) -> Bool {
  return lhs.rawValue < rhs.rawValue
}
