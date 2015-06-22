import Foundation

struct AppleCore {

  enum TraceLevel {
    case None
    case EntitiesOnly
    case All
  }

  static var traceLevel = TraceLevel.EntitiesOnly

  static func traceEntity(entityName: String) {
    if traceLevel == .None {
      return
    }

    println("Monkey ---> Entity \(entityName)")
  }

  static func traceID(id: String) {
    if traceLevel == .None {
      return
    }

    println("Monkey      ID: \(id)")
  }

  static func traceExisting() {
    if traceLevel == .None {
      return
    }

    println("Monkey      Existing - no update")
  }
  
  static func traceInsert() {
    if traceLevel == .None {
      return
    }

    println("Monkey      Inserting")
  }
  
  static func traceUpdate() {
    if traceLevel == .None {
      return
    }

    println("Monkey      Update")
  }
  
  static func trace(message: String?) {
    if let msg = message {
      println("Monkey      \(msg)")
    }
  }
  

}