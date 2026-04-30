//
//  ContentView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

enum AppTab: Hashable {
    case floorPlan, assistant, camera, explore, profile
}

/// Cross-tab signal: when ExploreView wants to hand off a building to the map,
/// it stamps `pendingBuildingId` and switches `selectedTab` to `.floorPlan`.
/// FloorPlanView consumes the id, flies the MKMapView there, and clears it.
final class MapNavigationCoordinator: ObservableObject {
    @Published var selectedTab: AppTab = .floorPlan
    @Published var pendingBuildingId: String?
}

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var mapNav = MapNavigationCoordinator()
    @State private var showCameraPulse = false

    var body: some View {
        Group {
            if !authService.didProbe {
                ZStack {
                    Color.slate50.ignoresSafeArea()
                    ProgressView()
                }
            } else if authService.enforcementOn && !authService.isAuthenticated {
                LoginView()
            } else {
                mainTabs
            }
        }
    }

    private var mainTabs: some View {
        ZStack {
            TabView(selection: $mapNav.selectedTab) {
                MapTabView()
                    .tag(AppTab.floorPlan)
                    .tabItem { Label("Map", systemImage: "map") }

                AssistantView()
                    .tag(AppTab.assistant)
                    .tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right") }

                CameraEntryView()
                    .tag(AppTab.camera)
                    .tabItem {
                        Label("Camera", systemImage: "camera")
                    }

                ExploreView()
                    .tag(AppTab.explore)
                    .tabItem { Label("Explore", systemImage: "list.bullet.rectangle") }

                ProfileView()
                    .tag(AppTab.profile)
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            }
            .background(Color.slate50)
            .environmentObject(mapNav)
        }
    }
}

#Preview("App") { ContentView() }
