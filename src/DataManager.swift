//
//  DataManager.swift
//  Virate
//
//  Created by Joost Lubach on 31/10/14.
//  Copyright (c) 2014 Joost Lubach. All rights reserved.
//

import CoreData
import BrightFutures
import QueryKit
import SwiftyJSON

public class DataManager<T: NSManagedObject> {

  convenience init(context: ManagedObjectContextConvertible) {
    self.init(entityName: NSStringFromClass(T), context: context)
  }

  init(entityName: String, context: ManagedObjectContextConvertible) {
    self.entityName = entityName
    self.context = context.managedObjectContext
  }

  public let entityName: String
  public let context:    ManagedObjectContext

  public lazy var entity: NSEntityDescription = {
    return NSEntityDescription.entityForName(
      self.entityName,
      inManagedObjectContext: self.context.underlyingContext
      )!
    }()

  /// Finds an object by its ID.
  public func findWithID(id: AnyObject) -> T? {
    let query = QuerySet<T>(context.underlyingContext, entityName)
    let mapper = DataMapper<NSManagedObject>(entityName: entityName, context: context)

    if let idMapping = mapper.IDMapping {
      var predicate = NSPredicate(format: "\(idMapping.attribute) == %@", argumentArray: [id])
      return query.filter(predicate)[0]
    } else {
      assertionFailure("\(entityName) does not have an ID mapping")
      return nil
    }
  }

  public func insert() -> T {
    return T(entity: entity, insertIntoManagedObjectContext: context.underlyingContext)
  }

  /// Finds or inserts an object from the given JSON. The id is taken from the "id" property.
  public func findOrInsertWithJSON(json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let id: AnyObject = DataMapper<T>(entityName: entityName, context: context).getIDFromJSON(json)
    return findWithID(id) ?? insertWithJSON(json, extra: extra)
  }

  /// Inserts or updates an object from the given JSON. The id is taken from the "id" property.
  public func insertOrUpdateWithJSON(json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let id: AnyObject = DataMapper<T>(entityName: entityName, context: context).getIDFromJSON(json)
    let object = findWithID(id) ?? insert()

    return update(object, withJSON: json, extra: extra)
  }

  /// Inserts an object from the given JSON.
  public func insertWithJSON(json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let object = insert()
    return update(object, withJSON: json, extra: extra)
  }

  /// Updates an object from the given JSON.
  public func update(object: T, withJSON json: JSON, extra: [String: AnyObject?] = [:]) -> T {
    let mapper = DataMapper<T>(entityName: entityName, context: context)
    mapper.mapJSON(json, toObject: object)

    for (key, value) in extra {
      object.setValue(value, forKey: key)
    }

    return object
  }

  /// Inserts a set of objects from a JSON array.
  public func insertSetWithJSON(json: JSON, extra: [String: AnyObject?] = [:], updateExisting: Bool = true, orderOffset: Int = 0) -> [T] {
    var set: [T] = []
    let mapper = DataMapper<T>(entityName: entityName, context: context)

    if let array = json.array {
      var object: T!
      var order = orderOffset

      for node in array {
        if mapper.IDMapping == nil {
          object = insertWithJSON(node, extra: extra)
        } else if updateExisting {
          object = insertOrUpdateWithJSON(node, extra: extra)
        } else {
          object = findOrInsertWithJSON(node, extra: extra)
        }
        if let orderKey = mapper.orderKey {
          object.setValue(order, forKey: orderKey)
        }

        set.append(object)
        order += 1
      }
    } else {
      assertionFailure("Expected array")
    }

    return set
  }

  public func deleteAll() -> Int {
    let querySet = QuerySet<NSManagedObject>(context.underlyingContext, entityName)
    return querySet.delete().count
  }
  
}
