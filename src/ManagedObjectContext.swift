import CoreData
import BrightFutures
import QueryKit

/// Wrapper around NSManagedObjectContext.
public class ManagedObjectContext: NSObject {

  /// Initializes the context with the given underlying context.
  public init(underlyingContext: NSManagedObjectContext) {
    self.underlyingContext = underlyingContext
  }

  /// Initializes the context with a new underlying context with the given options.
  public convenience init(concurrencyType: NSManagedObjectContextConcurrencyType = .PrivateQueueConcurrencyType, parentContext: ManagedObjectContext? = nil) {
    self.init(underlyingContext: NSManagedObjectContext(concurrencyType: concurrencyType))

    if let context = parentContext {
      underlyingContext.performBlock {
        self.underlyingContext.parentContext = context.underlyingContext
      }
    }
  }

  deinit {
    if isObserver {
      NSNotificationCenter.defaultCenter().removeObserver(self)
    }
  }

  // MARK: Properties

  /// The underlying NSManagedObjectContext instance.
  public let underlyingContext: NSManagedObjectContext

  /// Creates a QuerySet of given type for this context.
  public func query<T: NSManagedObject>(type: T.Type) -> QuerySet<T> {
    return QuerySet<T>(underlyingContext, NSStringFromClass(T))
  }

  /// Creates a data manager of given type for this context.
  public func manager<T: NSManagedObject>(type: T.Type) -> DataManager<T> {
    return DataManager<T>(context: self)
  }

  // MARK: - Operations

  public func insert<T: NSManagedObject>(type: T.Type) -> T {
    let entityName = NSStringFromClass(T)
    let entity = NSEntityDescription.entityForName(entityName, inManagedObjectContext: underlyingContext)!
    return T(entity: entity, insertIntoManagedObjectContext: underlyingContext)
  }

  /// Performs a block on this context, passing this context.
  public func performBlock(block: () -> Void) -> Future<Void> {
    var promise = Promise<Void>()

    underlyingContext.performBlock {
      block()
      promise.success()
    }

    return promise.future
  }

  /// Performs a block on this context, passing this context and waits until execution is finished.
  public func performBlockAndWait(block: () -> Void) {
    underlyingContext.performBlockAndWait(block)
  }

  /// Saves data asynchronously using a block.
  ///
  /// :returns: A future used to obtain a result status with.
  public func save(block: (ManagedObjectContext, NSErrorPointer) -> Void) -> Future<Void> {
    var error: NSError? = nil
    var promise = Promise<Void>()

    underlyingContext.performBlock {
      block(self, &error)

      if error == nil {
        self.saveChanges(error: &error)
      }

      if let err = error {
        promise.failure(err)
      } else {
        promise.success()
      }
    }

    return promise.future
  }

  /// Saves data synchronously.
  public func saveAndWait(error: NSErrorPointer = nil, block: (ManagedObjectContext) -> Void) -> Bool {
    var returnValue = false
    underlyingContext.performBlockAndWait {
      block(self)
      returnValue = self.saveChanges(error: error)
    }
    return returnValue
  }

  /// Saves any changes made in the context.
  public func saveChanges(saveParents: Bool = true, error: NSErrorPointer = nil) -> Bool {
    if !underlyingContext.hasChanges { return true }

    if saveParents {
      var context: NSManagedObjectContext! = underlyingContext
      while context != nil {
        var internalError: NSError? = nil
        if !context.save(&internalError) {
          println(internalError!)
          if error != nil {
            error.memory = internalError
          }
          return false
        }
        context = context.parentContext
      }
      return true
    } else {
      return underlyingContext.save(error)
    }
  }

  public func deleteObject(object: NSManagedObject) {
    underlyingContext.deleteObject(object)
  }

  /// Gets a copy of the given managed object in the current context.
  public func get<T: NSManagedObject>(object: T) -> T {
    let objectID = object.objectID
    return underlyingContext.objectWithID(objectID) as! T
  }

  // MARK: - Synchronization

  var isObserver = false
  var contextsToMergeChangesInto: [ManagedObjectContext] = []

  /// Makes sure that when this context is saved, its changed are merged into the target context.
  func mergeChangesInto(context: ManagedObjectContext) {
    if !isObserver {
      NSNotificationCenter.defaultCenter().addObserver(
        self,
        selector: "contextDidSave:",
        name: NSManagedObjectContextDidSaveNotification,
        object: underlyingContext
      )
      isObserver = true
    }

    contextsToMergeChangesInto.append(context)
  }

  func contextDidSave(notification: NSNotification) {
    for context in contextsToMergeChangesInto {
      context.underlyingContext.performBlock {
        context.underlyingContext.mergeChangesFromContextDidSaveNotification(notification)
      }
    }
  }

}

protocol ManagedObjectContextConvertible {
  var managedObjectContext: ManagedObjectContext { get }
}

extension ManagedObjectContext: ManagedObjectContextConvertible {

  var managedObjectContext: ManagedObjectContext {
    return self
  }

}

extension NSManagedObjectContext: ManagedObjectContextConvertible {

  var managedObjectContext: ManagedObjectContext {
    return ManagedObjectContext(underlyingContext: self)
  }
  
}
