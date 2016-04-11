//
//  Goal.swift
//  SmartGoals
//
//  Created by Curt Clifton on 2/2/16.
//  Copyright © 2016 curtclifton.net. All rights reserved.
//

import Foundation

extension SGMGoal: ModelValueUpdatable {
    func updateFromValue<Value : ModelValue>(value: Value) {
        guard let goal = value as? Goal else {
            fatalError("Attempting to update SGMGoal from non-Goal value: \(value)")
        }
        
        self.title = goal.title
        self.outcomeDescription = goal.outcomeDescription
        self.evaluationMetricDescription = goal.evaluationMetricDescription
        self.roleSupported = SGMRole() // CCC, 4/10/2016. need to get from ID on goal to actual object, hrmm
        self.goalsSupported = nil // CCC, 4/10/2016.

        self.reviews = nil // CCC, 4/10/2016.
    }
}

public struct Goal: Reviewable {
    let identifier: Identifier<Goal>
    
    public let title: String
    public let outcomeDescription: String
    public let evaluationMetricDescription: String
    public let roleSupported: Identifier<Role>
    
    public let goalsSupported: [Identifier<Goal>]
    
    public let reviews: [Identifier<Review>]
}

