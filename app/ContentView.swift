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

struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var selected: AppTab = .floorPlan
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
            TabView(selection: $selected) {
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
        }
    }
}

#Preview("App") { ContentView() }
