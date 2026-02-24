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
                    .tabItem { Label("Ask AI", systemImage: "bubble.left.and.bubble.right") }

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

            /*
            // Floating center camera action to improve...
            VStack {
                Spacer()

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selected = .camera
                        showCameraPulse.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(selected == .camera ? Color.white : Color.blue600)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.black.opacity(0.15),
                                    radius: 14, x: 0, y: 10)
                            .overlay(
                                Circle()
                                    .stroke(
                                        selected == .camera
                                            ? Color.blue500
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )

                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(
                                selected == .camera
                                    ? Color.blue600
                                    : Color.white
                            )
                    }
                }
                .padding(.bottom, 20) // sits nicely above tab bar
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .bottom)
             */

        }
    }
}

#Preview("App") { ContentView() }
