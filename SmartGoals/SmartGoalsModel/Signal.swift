//
//  Signal.swift
//  SmartGoals
//
//  Created by Curt Clifton on 2/14/16.
//  Copyright © 2016 curtclifton.net. All rights reserved.
//

import Foundation
import CoreData

// CCC, 5/15/2016. Split out Signal subclasses. Make most functions internal, since we have our own module for these now.

/// A mappable signal producing values of type `Value`.
///
/// In general, clients must retain instances of `Signal` except as documented. The basic capture pattern is that a signal captures the blocks passed to `map` and `flatmap`. Those blocks capture both the signal returned by the mapping function.
///
/// N.B., anything captured by a block passed to `map` and `flatmap` will be retained until the `Signal` is released. Capturing strong `self` in one of these blocks is a great way to created a retain cycle.
public class Signal<Value> {

    public private(set) var currentValue: Value?
    private var observers: [Value -> ()] = []
    
    /// Pushes a new value on the signal.
    ///
    /// This is private so subclasses can prevent clients from pushing signals. Clients wishing to push signals should use `UpdatableSignal`.
    private func update(toValue value: Value) {
        currentValue = value
        notifyObservers(ofValue: value)
    }
    
    /// Calls `transform` for all events, pushing the result on the returned signal.
    public func map<OutValue>(transform: Value -> OutValue) -> Signal<OutValue> {
        let outSignal: Signal<OutValue> = createOutSignal()
        
        let observer: Value -> () = { newValue in
            let outValue = transform(newValue)
            outSignal.update(toValue: outValue)
        }
        
        addObserver(observer)
        return outSignal
    }
    
    /// Calls `transform` for all events, pushing the non-nil results on the returned signal.
    public func flatmap<OutValue>(transform: Value -> OutValue?) -> Signal<OutValue> {
        let outSignal: Signal<OutValue> = createOutSignal()
        
        let observer: Value -> () = { newValue in
            if let outValue = transform(newValue) {
                outSignal.update(toValue: outValue)
            }
        }
        
        addObserver(observer)
        return outSignal
    }

    //MARK: Private API

    private func notifyObservers(ofValue value: Value) {
        for observer in observers {
            observer(value)
        }
    }
    
    private func createOutSignal<OutValue>() -> Signal<OutValue> {
        return Signal<OutValue>()
    }
    
    private func addObserver(observer: Value -> ()) {
        observers.append(observer)
        if let existingValue = currentValue {
            observer(existingValue)
        }
    }
}

/// A signal to which client code can push new values.
public class UpdatableSignal<Value>: Signal<Value> {
    public convenience init(withInitialValue value: Value) {
        self.init()
        update(toValue: value)
    }
    
    public override init() {
        super.init()
    }
    
    public override func update(toValue value: Value) {
        super.update(toValue: value)
    }
}

// MARK: - Queues

// CCC, 5/15/2016. Extend Signal with fluent method to create queueSpecificSignal, make the init private
// CCC, 5/15/2016. Document memory management.
public class QueueSpecificSignal<Value>: Signal<Value> {
    private let sourceSignal: Signal<Value>
    private let notificationQueue: NSOperationQueue
    
    public init(signal: Signal<Value>, notificationQueue: NSOperationQueue) {
        self.sourceSignal = signal
        self.notificationQueue = notificationQueue
        super.init()

        signal.addObserver { value in
            self.update(toValue: value)
        }
    }
    
    /// Overrides `notifyObservers(ofValue:)` to push notifications on `notificationQueue`.
    override private func notifyObservers(ofValue value: Value) {
        let observers = self.observers
        notificationQueue.addOperationWithBlock { 
            for observer in observers {
                observer(value)
            }
        }
    }
}

// MARK: - One Shots

// CCC, 5/15/2016. Extend Signal with fluent method to create oneShotSignal, make the init private
// CCC, 5/15/2016. document memory management
public final class OneShotSignal<Value>: Signal<Value> {
    private let sourceSignal: Signal<Value>
    public init(signal: Signal<Value>) {
        self.sourceSignal = signal
        super.init()
        
        signal.addObserver { value in
            self.update(toValue: value)
        }
    }
    
    /// Override to clear `observers` after notifying.
    override private func notifyObservers(ofValue value: Value) {
        for observer in observers {
            observer(value)
        }
        observers = []
    }
    
    /// Override to suppress caching of `observer` if we have a value with which to notify it already.
    override private func addObserver(observer: Value -> ()) {
        if let existingValue = currentValue {
            observer(existingValue)
        } else {
            observers.append(observer)
        }
    }
    
    public var isPrimed: Bool {
        return currentValue != nil
    }
}

// MARK: - Delays

public final class DelayedSignal<Value>: Signal<Value> {
    private let sourceSignal: Signal<Value>
    private let delayInNanoseconds: Int64
    
    private init(signal: Signal<Value>, delay: NSTimeInterval) {
        self.sourceSignal = signal
        self.delayInNanoseconds = Int64(round(delay * 1e9))
        super.init()
        
        signal.map { newValue in
            let propagateTime = dispatch_time(0, self.delayInNanoseconds)
            let queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)
            dispatch_after(propagateTime, queue) {
                self.update(toValue: newValue)
            }
        }
    }
}

extension Signal {
    public func signal(withDelay delay: NSTimeInterval) -> DelayedSignal<Value> {
        let result = DelayedSignal(signal: self, delay: delay)
        return result
    }
}

// MARK: - Combinators

public final class Zip2Signal<InValue1, InValue2>: Signal<(InValue1?, InValue2?)> {
    private let signal1: Signal<InValue1>
    private let signal2: Signal<InValue2>
    
    private init(signal1: Signal<InValue1>, signal2: Signal<InValue2>) {
        self.signal1 = signal1
        self.signal2 = signal2
        super.init()
        
        signal1.map { value1 in
            self.update(toValue: (value1, self.signal2.currentValue))
        }
        
        signal2.map { value2 in
            self.update(toValue: (self.signal1.currentValue, value2))
        }
    }
}

extension Signal {
    public func signal<Value2>(zippingWith other: Signal<Value2>) -> Zip2Signal<Value, Value2> {
        let result = Zip2Signal(signal1: self, signal2: other)
        return result
    }
}

// MARK: - Core Data Fetching

/// Instantiates a signal that executes `fetchRequest` in `context`, passing the fetched objects through `transform` and propagating the non-nil results on the signal.
///
/// Expects 0 or 1 non-nil results for each fetch.
public func itemFetchSignal<Value>(fetchRequest fetchRequest: NSFetchRequest, context: NSManagedObjectContext, transform: AnyObject -> Value?) -> Signal<Value> {
    let signal = FetchSignal<Value>(fetchRequest: fetchRequest, context: context) { (results: [AnyObject]) -> Value? in
        let typedMatches = results.flatMap { transform($0) }
        assert(typedMatches.count <= 1)
        if let match = typedMatches.first {
            return match
        }
        return nil
    }
    return signal
}

/// Instantiates a signal that executes `fetchRequest` in `context`, passing the fetched objects through `transform` and propagating the non-nil results on the signal. 
/// 
/// If there are no non-nil results, will propagate an empty array if the context returns no matching results.
public func arrayFetchSignal<Value>(fetchRequest fetchRequest: NSFetchRequest, context: NSManagedObjectContext, transform: AnyObject -> Value?) -> Signal<[Value]> {
    let signal = FetchSignal<[Value]>(fetchRequest: fetchRequest, context: context) { (results: [AnyObject]) -> [Value]? in
        let typedMatches = results.flatMap { transform($0) }
        return typedMatches
    }
    return signal
}

final class FetchSignal<Value>: Signal<Value> {
    let fetchRequest: NSFetchRequest
    let context: NSManagedObjectContext
    let transform: [AnyObject] -> Value?
    
    /// Instantiates a signal that executes `fetchRequest` in `context`, passing the fetched objects through `transform` and propagating the result, if non-nil, on the signal.
    init(fetchRequest: NSFetchRequest, context: NSManagedObjectContext, transform: [AnyObject] -> Value?) {
        self.fetchRequest = fetchRequest
        self.context = context
        self.transform = transform
        super.init()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(FetchSignal.mocChanged(_:)), name: NSManagedObjectContextObjectsDidChangeNotification, object: context)
        fetchUpdates()
    }
    
    private func anyEntityMatches(userInfo userInfo: [NSObject: AnyObject], key: String) -> Bool {
        guard let objects = userInfo[key] as? NSSet else { return false }
        for object in objects {
            if let managedObject = object as? NSManagedObject {
                let moEntityName = managedObject.entity.name
                let fetchEntityName = fetchRequest.entityName
                let fetchRequestPredicate = fetchRequest.predicate
                if moEntityName == fetchEntityName {
                    if let pred = fetchRequestPredicate {
                        if pred.evaluateWithObject(managedObject) {
                            return true
                        }
                    } else {
                        // if there's no predicate at all, update on a name match
                        return true
                    }
                }
            }
        }
        return false
    }
    
    @objc(mocChanged:)
    private func mocChanged(notification: NSNotification) {
        guard let userInfo = notification.userInfo else { return }
        let matchFound = (anyEntityMatches(userInfo: userInfo, key: NSInsertedObjectsKey)
            || anyEntityMatches(userInfo: userInfo, key: NSDeletedObjectsKey)
            || anyEntityMatches(userInfo: userInfo, key: NSRefreshedObjectsKey)
            || anyEntityMatches(userInfo: userInfo, key: NSUpdatedObjectsKey))
        
        if matchFound {
            fetchUpdates()
        }
    }
    
    private func fetchUpdates() {
        context.performBlock { [weak self] _ in
            guard let strongSelf = self else { return }
            do {
                let fetchResults = try strongSelf.context.executeFetchRequest(strongSelf.fetchRequest)
                let transformedResult = strongSelf.transform(fetchResults)
                if let transformedResult = transformedResult {
                    strongSelf.update(toValue: transformedResult)
                }
            } catch {
                fatalError("Error running fetch request: \(error)")
            }
        }
    }
}
