//
//  Reviews.swift
//  SmartGoals
//
//  Created by Curt Clifton on 2/2/16.
//  Copyright © 2016 curtclifton.net. All rights reserved.
//

import Foundation
import CoreData

public protocol Reviewable { // CCC, 3/29/2016. what should be Reviewable?
    var reviews: [Review] { get }
}

extension SGMReview: ModelValueUpdatable {
    func updateFromValue<Value : ModelValue>(value: Value) {
        guard let review = value as? Review else {
            fatalError("Attempting to update SGMReview from non-Review value: \(value)")
        }
        self.date = review.date.timeIntervalSinceReferenceDate
        self.review = review.review
    }
}

public struct Review: ModelValue {
    public static var entityName: String {
        return SGMReview.entityName
    }
    
    public static var fetchRequest: NSFetchRequest {
        return SGMReview.fetchRequest()
    }
    
    public let identifier: Identifier<Review>
    
    public let date: NSDate
    public let review: String
    
    public init?(fromObject: AnyObject) {
        guard let object = fromObject as? SGMReview else {
            return nil
        }
        self.identifier = object.identifier
        self.date = NSDate(timeIntervalSinceReferenceDate: object.date)
        self.review = object.review ?? ""
    }
}

public func ==(lhs: Review, rhs: Review) -> Bool {
    return (lhs.identifier == rhs.identifier
        && lhs.date == rhs.date
        && lhs.review == rhs.review)
}
