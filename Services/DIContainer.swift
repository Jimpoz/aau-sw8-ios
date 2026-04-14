//
//  DIContainer.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation
import Combine

@MainActor
final class DIContainer: ObservableObject {
    @Published var spatial: SpatialQuerying?
    @Published var llm: LLMChatting?
    @Published var floorPlanService = FloorPlanService()
    @Published var navigationService = NavigationService()
    @Published var locationTrackingService = LocationTrackingService()

    init(spatial: SpatialQuerying? = nil, llm: LLMChatting? = nil) {
        self.spatial = spatial
        self.llm = llm ?? AssistantService()
    }
}
