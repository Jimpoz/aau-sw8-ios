//
//  ProfileView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var themeSettings: ThemeSettings
    @State private var displayName: String = "John Doe"
    @State private var goldMember: Bool = true
    @State private var avoidStairs: Bool = true
    @State private var voiceGuidance: Bool = false
    @State private var elevatorsOnly: Bool = false
    @State private var showRoomPhotoUpload: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue500, .blue700], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
                        Text(initials(from: displayName))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(Color.slate900)
                        Text(goldMember ? "Gold Member" : "Member")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.slate500)
                    }
                    Spacer()
                }
                .padding(.top, 12)

                // Stats
                HStack(spacing: 12) {
                    StatCard(title: "Total Distance", value: "4.2 km")
                    StatCard(title: "Steps", value: "5,430")
                }

                // Preferences
                VStack(spacing: 0) {
                    HStack {
                        Text("Navigation Preferences")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.slate700)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.slate50)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

                    VStack(spacing: 16) {
                        ToggleRow(title: "Avoid Stairs", isOn: $avoidStairs)
                        ToggleRow(title: "Voice Guidance", isOn: $voiceGuidance)
                        ToggleRow(title: "Use Elevators Only", isOn: $elevatorsOnly)
                    }
                    .padding(16)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.slate100))

                // Theme
                VStack(spacing: 0) {
                    HStack {
                        Text("Appearance")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.slate700)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.slate50)
                    .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.slate100), alignment: .bottom)

                    VStack(spacing: 16) {
                        HStack {
                            Text("Dark Mode")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.slate600)
                            Spacer()
                            Toggle("", isOn: $themeSettings.isDarkMode)
                                .labelsHidden()
                        }
                    }
                    .padding(16)
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.slate100))

                Button {
                    showRoomPhotoUpload = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.on.rectangle")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Upload Room Photos")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.blue500)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue500.opacity(0.2)))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 6)

                Button(role: .destructive) { /* logout */ } label: {
                    Text("Log Out")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.red.opacity(0.15)))
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color.slate50)
        .sheet(isPresented: $showRoomPhotoUpload) {
            RoomPhotoUploadView()
        }
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2).map { $0.first.map(String.init) ?? "" }.joined()
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.slate400)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.slate800)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Color.slate600)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

#Preview("Profile") { ProfileView() }
