//
//  Item.swift
//  FlowlyPlanner
//
//  Created by Gavin Sparks on 12/12/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
