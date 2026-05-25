//
//  DIContainer.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import CoreLocation
import Foundation
import Combine

@MainActor
final class DIContainer: ObservableObject {
    @Published var spatial: SpatialQuerying?
    @Published var llm: LLMChatting?
    @Published var floorPlanService = FloorPlanService()
    @Published var navigationService = NavigationService()
    @Published var locationManager = LocationManager()
    @Published var currentCampusId: String?
    @Published var currentBuildingId: String?
    @Published var currentFloorIndex: Int?
    @Published var forcedUserSpaceId: String?
    @Published var forcedUserCoordinate: CLLocationCoordinate2D?
    @Published var lastKnownUserCoordinate: CLLocationCoordinate2D?

    init(spatial: SpatialQuerying? = nil, llm: LLMChatting? = nil) {
        self.spatial = spatial
        self.llm = llm ?? AssistantService()
    }
}
