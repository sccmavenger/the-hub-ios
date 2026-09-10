//
//  Item.swift
//  TheHub
//
//  Created by Danny Jr on 9/10/26.
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
