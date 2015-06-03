import CoreData
import SwiftyJSON

private typealias MappingEntry = (id: StandardMapping?, orderKey: String?, attributes: [Mapping])
private var Mappings:  [String: MappingEntry] = [:]

private func DefaultIDMapping() -> StandardMapping {
  return IntegerMapping("id")
}

protocol Mapping {

  func mapValueFromJSON(json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext)

}

public class CustomMapping<T: NSManagedObject>: Mapping {

  typealias Handler = (T, json: JSON, context: ManagedObjectContext) -> ()

  init(_ handler: Handler) {
    self.handler = handler
  }

  let handler: Handler

  func mapValueFromJSON(json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext) {
    handler(object as! T, json: json, context: context)
  }

}

public class StandardMapping: Mapping {

  convenience init(_ attribute: String) {
    self.init(attribute, from: StringUtil.underscore(attribute))
  }

  init(_ attribute: String, from jsonKey: String) {
    self.attribute = attribute
    self.jsonKey = jsonKey
  }

  let jsonKey: String
  let attribute: String

  func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    return nil
  }

  func mapValueFromJSON(json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext) {
    let value: AnyObject? = getValueFromJSON(json, context: context)
    object.setValue(value, forKey: attribute)
  }

}

public class NumberMapping: StandardMapping {

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if let number = json[jsonKey].number {
      return getNumber(number)
    } else if json[jsonKey].isEmpty {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected number")
      return nil
    }
  }

  func getNumber(number: NSNumber) -> AnyObject {
    return 0
  }

}

public class IntegerMapping: NumberMapping {
  override func getNumber(number: NSNumber) -> AnyObject {
    return number.integerValue
  }
}
public class DoubleMapping: NumberMapping {
  override func getNumber(number: NSNumber) -> AnyObject {
    return number.doubleValue
  }
}
public class BooleanMapping: NumberMapping {
  override func getNumber(number: NSNumber) -> AnyObject {
    return number.boolValue
  }
}

public class StringMapping: StandardMapping {

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if let string = json[jsonKey].string {
      return string
    } else if json[jsonKey].isEmpty {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected string")
      return nil
    }
  }

}

public class DateMapping: StandardMapping {

  var dateFormat: String = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
  var locale: NSLocale   = NSLocale(localeIdentifier: "en_US_POSIX")

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if let string = json[jsonKey].string {
      let formatter        = NSDateFormatter()
      formatter.dateFormat = dateFormat
      formatter.locale     = locale
      return formatter.dateFromString(string)
    } else if let number = json[jsonKey].number {
      let timestamp = number.doubleValue
      return NSDate(timeIntervalSince1970: timestamp)
    } else if json[jsonKey].isEmpty {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected string or number")
      return nil
    }
  }

}

public class Base64Mapping: StringMapping {

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if let string = super.getValueFromJSON(json, context: context) as? String {
      let data = NSData(base64EncodedString: string, options: nil)
      if data == nil {
        assertionFailure("Key `\(jsonKey)`: invalid Base64 string")
      }
      return data
    } else {
      return nil
    }
  }

}

public class ToOneRelationshipMapping<T: NSManagedObject>: StandardMapping {

  convenience init(_ attribute: String, updateExisting: Bool = true) {
    self.init(attribute, from: StringUtil.underscore(attribute), updateExisting: updateExisting)
  }

  init(_ attribute: String, from jsonKey: String, ordered: Bool = false, updateExisting: Bool = true) {
    self.updateExisting = updateExisting
    super.init(attribute, from: jsonKey)
  }

  let updateExisting: Bool

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if json[jsonKey].type == .Dictionary {
      let manager = DataManager<T>(context: context)
      if updateExisting {
        return manager.insertOrUpdateWithJSON(json[jsonKey])
      } else {
        return manager.findOrInsertWithJSON(json[jsonKey])
      }
    } else if json[jsonKey].isEmpty {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected JSON dictionary")
      return nil
    }
  }

}

public class ToManyRelationshipMapping<T: NSManagedObject>: StandardMapping {

  convenience init(_ attribute: String, ordered: Bool = false, updateExisting: Bool = true) {
    self.init(attribute, from: StringUtil.underscore(attribute), ordered: ordered, updateExisting: updateExisting)
  }

  init(_ attribute: String, from jsonKey: String, ordered: Bool = false, updateExisting: Bool = true) {
    self.ordered = ordered
    self.updateExisting = updateExisting
    super.init(attribute, from: jsonKey)
  }

  let ordered: Bool
  let updateExisting: Bool

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    if json[jsonKey].type == .Array {
      let manager = DataManager<T>(context: context)
      return manager.insertSetWithJSON(json[jsonKey], updateExisting: updateExisting)
    } else if json[jsonKey].isEmpty {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected JSON array")
      return nil
    }
  }

  override func mapValueFromJSON(json: JSON, toObject object: NSManagedObject, inContext context: ManagedObjectContext) {
    if let array = getValueFromJSON(json, context: context) as? [T] {
      if ordered {
        object.setValue(NSOrderedSet(array: array), forKey: attribute)
      } else {
        object.setValue(NSSet(array: array), forKey: attribute)
      }
    }
  }

}

public class RelatedObjectIDMapping<T: NSManagedObject>: StandardMapping {

  init(_ attribute: String) {
    super.init(attribute, from: RelatedObjectIDMapping<T>.defaultJSONKey(attribute))
  }

  override init(_ attribute: String, from jsonKey: String) {
    super.init(attribute, from: jsonKey)
  }

  class func defaultJSONKey(attribute: String) -> String {
    return StringUtil.underscore(attribute) + "_id"
  }

  override func getValueFromJSON(json: JSON, context: ManagedObjectContextConvertible) -> AnyObject? {
    let entityName = NSStringFromClass(T)
    let manager = DataManager<NSManagedObject>(entityName: entityName, context: context)

    var object: NSManagedObject!

    if let number = json[jsonKey].number {
      object = manager.findWithID(number.integerValue)
    } else if let string = json[jsonKey].string {
      object = manager.findWithID(string)
    } else if json[jsonKey].isEmpty {
      return nil
    } else {
      assertionFailure("Key `\(jsonKey)`: expected JSON array")
    }

    if object != nil {
      return object
    } else {
      assertionFailure("Key `\(jsonKey)`: \(entityName) with ID \(json[jsonKey]) not found")
      return nil
    }
  }

}

public class DataMapper<T: NSManagedObject> {

  convenience init(context: ManagedObjectContextConvertible) {
    self.init(entityName: NSStringFromClass(T), context: context)
  }

  init(entityName: String, context: ManagedObjectContextConvertible) {
    self.entityName = entityName
    self.context    = context.managedObjectContext
  }

  let entityName: String
  let context: ManagedObjectContext

  func mapJSON(json: JSON, toObject object: NSManagedObject) {
    // Map ID.
    if let mapping = IDMapping {
      mapping.mapValueFromJSON(json, toObject: object, inContext: context)
    }

    // Map other attributes.
    for mapping in attributeMappings {
      mapping.mapValueFromJSON(json, toObject: object, inContext: context)
    }
  }

  func getIDFromJSON(json: JSON) -> AnyObject! {
    if let mapping = IDMapping {
      return mapping.getValueFromJSON(json, context: context)!
    } else {
      assertionFailure("\(entityName) has no ID mapping")
      return nil
    }
  }


  // MARK: - Matadata

  var attributeMappings: [Mapping] {
    assert(entityName != "NSManagedObject", "you need a specialized version of DataMapper")

    if let entry = Mappings[entityName] {
      return entry.attributes
    } else {
      return []
    }
  }

  var IDMapping: StandardMapping? {
    assert(entityName != "NSManagedObject", "you need a specialized version of DataMapper")

    if let entry = Mappings[entityName] {
      return entry.id
    } else {
      return DefaultIDMapping()
    }
  }

  var orderKey: String? {
    assert(entityName != "NSManagedObject", "you need a specialized version of DataMapper")

    if let entry = Mappings[entityName] {
      return entry.orderKey
    } else {
      return nil
    }
  }

  class func addMapping<TMapping: Mapping>(mapping: TMapping) {
    let entityName = NSStringFromClass(T)

    if Mappings[entityName] == nil {
      Mappings[entityName] = (id: DefaultIDMapping(), orderKey: nil, attributes: [])
    }

    Mappings[entityName]!.attributes.append(mapping)
  }

  class func mapIDWith(mapping: StandardMapping?) {
    let entityName = NSStringFromClass(T)

    if Mappings[entityName] == nil {
      Mappings[entityName] = (id: DefaultIDMapping(), orderKey: nil, attributes: [])
    }

    Mappings[entityName]!.id = mapping
  }

  class func mapOrderTo(key: String?) {
    let entityName = NSStringFromClass(T)

    if Mappings[entityName] == nil {
      Mappings[entityName] = (id: DefaultIDMapping(), orderKey: nil, attributes: [])
    }
    
    Mappings[entityName]!.orderKey = key
  }
  
}
