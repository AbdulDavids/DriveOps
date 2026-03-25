//
//  Item.swift
//  DriveOps
//
//  Created by Abdul Baari Davids on 2026/03/25.
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
