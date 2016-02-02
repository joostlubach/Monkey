import Foundation
import SwiftyJSON

public struct APIError: ErrorType {

  init(type: APIErrorType, status: Int, message: String?) {
    self.type = type
    self.status = status
    self.message = message
  }

  init(type: APIErrorType, status: Int) {
    self.type = type
    self.status = status
    self.message = nil
  }

  init(type: APIErrorType) {
    self.type = type
    self.status = nil
    self.message = nil
  }

  public let type: APIErrorType
  public let status: Int?
  public let message: String?

  internal(set) public var json: JSON?
  internal(set) public var data: NSData?
  internal(set) public var underlyingError: NSError?

}

extension APIError: CustomStringConvertible, CustomDebugStringConvertible {

  public var description: String {
    let typeDesc = status != nil ? "\(status!) \(type.description)" : type.description

    if let message = message {
      return "Error (\(typeDesc)) \(message)"
    } else {
      return "Error (\(typeDesc))"
    }
  }

  public var debugDescription: String {
    return description
  }

}

public enum APIErrorType: Int {

  /// Status 0
  case NotReachable     = 0

  /// Data was not formatted properly (e.g. JSON was expected). Could be caused by bad connection,
  /// so treated as `NotReachable`.
  case InvalidData      = 10

  /// Client errors
  case NotAuthorized    = 401
  case Forbidden        = 403
  case NotFound         = 404
  case BadRequest       = 400
  case OtherClientError = 499

  /// Server error
  case ServerError      = 500

  /// Whether this error signifies a client error.
  public var clientError: Bool {
    return (400..<500) ~= rawValue
  }

  /// Whether this error signifies a server error.
  public var serverError: Bool {
    return rawValue >= 500
  }

  /// Whether this error signifies some problem with the connection.
  public var connectionError: Bool {
    return !clientError && !serverError
  }

}

extension APIErrorType: CustomStringConvertible, CustomDebugStringConvertible {

  public var description: String {
    switch self {
    case .NotReachable:     return "Not reachable"
    case .InvalidData:      return "Invalid data"

    case .BadRequest:       return "Bad request"
    case .NotAuthorized:    return "Not authorized"
    case .Forbidden:        return "Forbidden"
    case .NotFound:         return "Not Found"
    case .OtherClientError: return "Other client error"

    case .ServerError:      return "Server error"
    }
  }

  public var debugDescription: String {
    return description
  }
  
}