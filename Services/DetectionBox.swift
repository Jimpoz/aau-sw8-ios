//
//  BoxBoundaries.swift
//  aau-sw8-ios
//
//  Created by jimpo on 05/03/26.
//

import CoreGraphics
import Foundation

struct DetectionBox: Identifiable {
    let id = UUID()
    let rect: CGRect
    let label: String
    let confidence: Float
}
