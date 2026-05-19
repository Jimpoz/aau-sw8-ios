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
    let isLandmarkMatch: Bool
    let landmarkName: String?

    init(
        rect: CGRect,
        label: String,
        confidence: Float,
        isLandmarkMatch: Bool = false,
        landmarkName: String? = nil
    ) {
        self.rect = rect
        self.label = label
        self.confidence = confidence
        self.isLandmarkMatch = isLandmarkMatch
        self.landmarkName = landmarkName
    }
}
