import Foundation

public struct Monkey {

  public static let ErrorDomain = "co.mosdev.Monkey-API"
  public static let SessionKey  = "co.mosdev.Monkey-APISession"

  public enum ErrorCodes: Int {
    case HTTPError = 10
    case InvalidJSON = 100
  }

  public enum TraceLevel: Int {
    case None                = 0
    case RequestsOnly        = 1
    case RequestsAndStatuses = 2
    case All                 = 10

    func lowerThan(other: TraceLevel) -> Bool {
      return rawValue < other.rawValue
    }

    func higherThan(other: TraceLevel) -> Bool {
      return rawValue > other.rawValue
    }

  }

  public static var traceLevel: TraceLevel = .RequestsAndStatuses


  static func readSessionFromUserDefaults() -> APISession? {
    let userDefaults = NSUserDefaults.standardUserDefaults()

    if let data = userDefaults.dataForKey(SessionKey) {
      return (NSKeyedUnarchiver.unarchiveObjectWithData(data) as! APISession)
    } else {
      return nil
    }
  }

  static func writeSessionToUserDefaults(sessionOrNil: APISession?) {
    let userDefaults = NSUserDefaults.standardUserDefaults()

    if let session = sessionOrNil {
      let data = NSKeyedArchiver.archivedDataWithRootObject(session)
      userDefaults.setObject(data, forKey: SessionKey)
    } else {
      userDefaults.removeObjectForKey(SessionKey)
    }
  }

}