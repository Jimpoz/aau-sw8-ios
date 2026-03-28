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
    @State private var selected: AppTab = .floorPlan
    @State private var showCameraPulse = false

    var body: some View {
        ZStack {
            TabView(selection: $selected) {
                FloorPlanView()
                    .tag(AppTab.floorPlan)
                    .tabItem { Label("Map", systemImage: "map") }

                AssistantView()
                    .tag(AppTab.assistant)
                    .tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right") }

                CameraView()
                    .tag(AppTab.camera)
                    .tabItem {
                        Label("Camera", systemImage: "camera")
                    }
                    .toolbarBackground(.visible, for: .tabBar)
                    .toolbarBackground(Color.black.opacity(0.8), for: .tabBar)

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
