//
//  FloorPlanViewModel.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import SwiftUI
import Combine

final class FloorPlanViewModel: ObservableObject {
    @Published var availableFloors: [Int] = []           // source-controlled by backend later
    @Published var availableFloorLabels: [String]? = nil // e.g., ["L1","L2","L3","G","B1"]
    @Published var selectedFloor: Int = 0

    // Pan/zoom state
    @Published var scale: CGFloat = 16
    @Published var offset: CGSize = .zero

    // Results UI stubs
    @Published var highlightedIDs: Set<String> = []
    @Published var routeIDs: [String] = []

    func resetView() {
        scale = 16
        offset = .zero
    }

    func clearHighlights() {
        highlightedIDs.removeAll()
        routeIDs.removeAll()
    }
}
