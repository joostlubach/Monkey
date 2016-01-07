import Foundation

public let APIClientDidAuthenticateNotification = "co.mosdev.Monkey.APIClientDidAuthenticate"
public let APIClientDidUnauthenticateNotification = "co.mosdev.Monkey.APIClientDidAuthenticate"

public enum TraceLevel: Int {
  case None                = 0
  case RequestsOnly        = 1
  case RequestsAndStatuses = 2
  case All                 = 10
}

extension TraceLevel: Comparable {}

public func <(lhs: TraceLevel, rhs: TraceLevel) -> Bool {
  return lhs.rawValue < rhs.rawValue
}