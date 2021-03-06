//
//  SmartGoalsModel.swift
//  SmartGoals
//
//  Created by Curt Clifton on 2/2/16.
//  Copyright © 2016 curtclifton.net. All rights reserved.
//

import CoreData
import Foundation
import Reactionary

/// This façade is the public interface to the model.
///
/// It vends signals to which clients can subscribe to get current model values. It provides methods for instantiating and updating objects in the database from model values.
public final class SmartGoalsModel {
    private let managedObjectContext: SmartGoalsManagedObjectContext

    /// Persistent reading MOC, lazily instantiated.
    private lazy var readingManagedObjectContext: SmartGoalsManagedObjectContext = {
        let parent = self.managedObjectContext
        let name = "reading child for \(parent.name)"
        let result = SmartGoalsManagedObjectContext(name: name, parentMOC: parent)
        result.retainsRegisteredObjects = true
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(SmartGoalsModel.parentMOCDidSave(_:)), name: NSManagedObjectContextDidSaveNotification, object: parent)

        return result
    }()
    
    init(managedObjectContext: SmartGoalsManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }

    //MARK: Public API
    
    /// Instantiates an object corresponding to the given type and returns its identifier.
    ///
    /// The identifier is returned immediately even though the object may be instantiated on a background queue. Clients can subscribe to the value signal for the identifier to be notified as soon the object exists.
    public func instantiateObjectOfType<Value: ModelValue>(type: Value.Type) -> Identifier<Value> {
        let identifier = Identifier<Value>()
        let transactionContext = transactionWritingContext()
        type.instantiateInContext(transactionContext, identifier: identifier)
        saveWritingContext(transactionContext)
        return identifier
    }
    
    /// Instantiates an object corresponding to the given type and returns a value signal for it.
    ///
    /// Pushes new values whenever the underlying object is updated. Values are pushed on the main queue.
    public func valueSignalForNewInstanceOfType<Value: ModelValue>(type: Value.Type) -> Signal<Result<Value, FetchError>> {
        let identifier = instantiateObjectOfType(type)
        let result = valueSignalForIdentifier(identifier)
        return result
    }

    /// Returns a signal vending new values for the item with the given identifier.
    ///
    /// Pushes new values whenever the underlying object is updated. Values are pushed on the main queue.
    public func valueSignalForIdentifier<Value: ModelValue>(identifier: Identifier<Value>) -> Signal<Result<Value, FetchError>> {
        let fetchRequest = Value.fetchRequest
        fetchRequest.predicate = identifier.predicate
        let newSignal = itemFetchSignal(fetchRequest: fetchRequest, context: self.readingManagedObjectContext) {
            return Value.init(fromObject: $0)
        }
        
        let mainQueueSignal = newSignal.signal(onQueue: .mainQueue())
        return mainQueueSignal
    }
    
    /// Returns a signal vending all values for items of `type`.
    ///
    /// Pushes all values whenever any one of them changes. Values are pushed on the main queue.
    public func valuesSignalForType<Value: ModelValue>(type: Value.Type) -> Signal<[Value]> {
        let fetchRequest = type.fetchRequest
        let newSignal = arrayFetchSignal(fetchRequest: fetchRequest, context: self.readingManagedObjectContext) {
            return type.init(fromObject: $0)
        }
        
        let mainQueueSignal = newSignal.signal(onQueue: .mainQueue())
        return mainQueueSignal
    }
    
    /// Updates the corresponding model object based on `value`.
    public func update<Value: ModelValue>(fromValue value:Value) {
        let transactionContext = transactionWritingContext()
        value.updateInContext(transactionContext)
        self.saveWritingContext(transactionContext)
    }
    
    /// Deletes the model object corresponding to `value`.
    public func delete<Value: ModelValue>(value value:Value) {
        let transactionContext = transactionWritingContext()
        value.deleteInContext(transactionContext)
        self.saveWritingContext(transactionContext)
    }
    
    /// Begins an atomic update session.
    ///
    /// - returns: an opaque token that should be passed to `update(fromValue:withToken:)` for subseqent updates in the session, and to `endUpdates(forToken:)` to end the session.
    /// - seeAlso: `update(fromValue:withToken:) for adding updates to the session
    /// - seeAlso: `endUpdates(forToken:) for ending the session
    public func beginUpdates() -> UpdateSessionToken {
        let token = UpdateSessionToken(writingContext: transactionWritingContext())
        return token
    }
    
    /// Updates the corresponding model object based on `value`, delaying writes until the session is ended with `endUdpates(forToken:)`
    /// - seeAlso: `beginUpdates()` for starting a session and getting its token
    public func update<Value: ModelValue>(fromValue value:Value, withToken token: UpdateSessionToken) {
        precondition(!token.isSessionEnded)
        value.updateInContext(token.writingContext)
    }
    
    /// Deletes the model object corresponding to `value`, delaying writes until the session is ended with `endUdpates(forToken:)`
    /// - seeAlso: `beginUpdates()` for starting a session and getting its token
    public func delete<Value: ModelValue>(value value:Value, withToken token: UpdateSessionToken) {
        precondition(!token.isSessionEnded)
        value.deleteInContext(token.writingContext)
    }
    
    /// Ends an atomic update session.
    /// - seeAlso: `beginUpdates()` for starting a session and getting its token
    /// - seeAlso: `update(fromValue:withToken:) for adding updates to the session
    public func endUpdates(forToken token: UpdateSessionToken) {
        precondition(!token.isSessionEnded)
        token.isSessionEnded = true
        self.saveWritingContext(token.writingContext)
    }
    
    //MARK: Private API
    
    private func transactionWritingContext() -> SmartGoalsManagedObjectContext {
        let name = "writing child for \(self.managedObjectContext.name)"
        let result = SmartGoalsManagedObjectContext(name: name, parentMOC: self.managedObjectContext)
        return result
    }
    
    private func saveWritingContext(context: SmartGoalsManagedObjectContext) {
        context.performBlock {
            do {
                try context.save()
                if let parentContext = context.parentContext as? SmartGoalsManagedObjectContext {
                    parentContext.performBlock {
                        do {
                            try parentContext.save()
                        } catch {
                            self.handleSaveError(error, managedObjectContext: parentContext)
                        }
                    }
                }
            } catch {
                self.handleSaveError(error, managedObjectContext: context)
            }
        }
    }
    
    private func handleSaveError(error: ErrorType, managedObjectContext: SmartGoalsManagedObjectContext) {
        NSLog("Unrecoverable failure saving managed object context \(managedObjectContext.name):\n\(error)")
        fatalError()
    }
    
    @objc(parentMOCDidSave:)
    private func parentMOCDidSave(notification: NSNotification) {
        readingManagedObjectContext.performBlock {
            self.readingManagedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
        }
    }
}

/// An opaque token used to begin and end atomic update transactions.
public class UpdateSessionToken {
    private let writingContext: SmartGoalsManagedObjectContext
    private var isSessionEnded = false
    
    private init(writingContext: SmartGoalsManagedObjectContext) {
        self.writingContext = writingContext
    }
}

//MARK: - ModelValue
protocol ModelValueUpdatable {
    func updateFromValue<Value: ModelValue>(value: Value)
}

public protocol ModelValue {
    static var entityName: String { get }
    static var fetchRequest: NSFetchRequest { get }
    
    var identifier: Identifier<Self> { get }
    
    /// For bridging from CoreData, ModelValues can be initialized from any object, failing if `fromObject` is not an instance of the appropriate object type.
    init?(fromObject: AnyObject)
}

/// internal extension, hidden from clients
extension ModelValue {
    static func instantiateInContext(context: SmartGoalsManagedObjectContext, identifier: Identifier<Self>) {
        context.performBlock {
            let entityName = self.entityName
            let object = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: context)
            guard let result = object as? SGMIdentifiedObject else {
                fatalError("Instantiated object for entity name “\(entityName)” is of type “\(object.dynamicType)”; expected “\(Self.self)”")
            }
            result.sgmIdentifier = identifier.uuid
        }
    }

    func updateInContext(context: SmartGoalsManagedObjectContext) {
        let fetchRequest = self.dynamicType.fetchRequest
        fetchRequest.predicate = self.identifier.predicate
        context.performBlock { () -> () in
            do {
                let fetchResult = try context.executeFetchRequest(fetchRequest)
                guard let object = fetchResult.first as? ModelValueUpdatable else {
                    // This shouldn't be fatal. With data races, the object could be gone from a simultaneous delete.
                    return
                }
                object.updateFromValue(self)
            } catch {
                fatalError("error fetching backing object for \(self):\n\(error)")
            }
        }
    }
    
    func deleteInContext(context: SmartGoalsManagedObjectContext) {
        let fetchRequest = self.dynamicType.fetchRequest
        fetchRequest.predicate = self.identifier.predicate
        context.performBlock { () -> () in
            do {
                let fetchResult = try context.executeFetchRequest(fetchRequest)
                guard let object = fetchResult.first as? NSManagedObject else {
                    fatalError("no existing object found for updating \(self)")
                }
                context.deleteObject(object)
            } catch {
                fatalError("error fetching backing object for \(self):\n\(error)")
            }
        }
    }
}

private var _sharedModelVendor: OneShotSignal<SmartGoalsModel>?
private var _modelSpinUpQueue: NSOperationQueue?

/// Returns a `OneShotSignal` that vends a model singleton on the main queue.
public func sharedModelVendor() -> OneShotSignal<SmartGoalsModel> {
    if let existingVendor = _sharedModelVendor {
        return existingVendor
    }
    let updatableSignal = UpdatableSignal<SmartGoalsModel>()
    let mainSignal = updatableSignal.signal(onQueue: .mainQueue())
    _sharedModelVendor = mainSignal.oneShotSignal()
    
    let queue = NSOperationQueue()
    _modelSpinUpQueue = queue
    queue.qualityOfService = .UserInteractive
    queue.addOperationWithBlock {
        // CCC, 2/13/2016. We're using an in-memory store for now. Will need to switch to a persistent store once the model is sorted. Take out this delay then:
        sleep(1) // simulate delay so app start-up is more like a disk-based store
        let rootManagedObjectContext: SmartGoalsManagedObjectContext = SmartGoalsManagedObjectContext(name: "Root Context")
        let sharedModel = SmartGoalsModel(managedObjectContext: rootManagedObjectContext)
        updatableSignal.update(toValue: sharedModel)
    }

    return _sharedModelVendor! // instantiated above
}
