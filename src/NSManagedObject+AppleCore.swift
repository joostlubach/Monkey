import CoreData

extension NSManagedObject {

  var context: ManagedObjectContext? {
    if let moc = managedObjectContext {
      return ManagedObjectContext(underlyingContext: moc)
    } else {
      return nil
    }
  }

}