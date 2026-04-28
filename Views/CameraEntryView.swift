//
//  CameraEntryView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import SwiftUI

struct CameraEntryView: View {
    @State private var openCamera = false
    @State private var openRoomScan = false
    @State private var showStub: StubAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    actionsCard
                }
                .padding(16)
            }
            .background(Color.slate50)
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $openCamera) {
                ZStack(alignment: .topLeading) {
                    CameraView()
                    Button {
                        openCamera = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .padding(.top, 60)
                    .padding(.leading, 16)
                }
            }
            .sheet(isPresented: $openRoomScan) {
                RoomPhotoUploadView()
            }
            .alert(item: $showStub) { stub in
                Alert(
                    title: Text(stub.title),
                    message: Text(stub.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(spacing: 12) {
            Text("Scan rooms, signs and QR codes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.slate500)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.blue100)
                        .frame(width: 96, height: 96)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(Color.blue600)
                }
                .padding(.top, 8)

                Text("Ready to scan")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.slate800)

                Text("Point your camera at a sign, QR code or building marker.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.slate500)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.slate100))
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.slate700)

            VStack(spacing: 0) {
                ActionRow(
                    icon: "camera.fill",
                    iconBg: Color.blue600,
                    title: "Open camera",
                    subtitle: "Start the live detection feed."
                ) {
                    openCamera = true
                }
                Divider().padding(.leading, 56)

                ActionRow(
                    icon: "square.and.arrow.up.fill",
                    iconBg: Color(red: 0.20, green: 0.65, blue: 0.45),
                    title: "Scan Room",
                    subtitle: "Upload four photos (N/E/S/W) to summarize a room."
                ) {
                    openRoomScan = true
                }
                Divider().padding(.leading, 56)

                ActionRow(
                    icon: "qrcode.viewfinder",
                    iconBg: Color(red: 0.55, green: 0.30, blue: 0.85),
                    title: "Scan QR Code",
                    subtitle: "Decode a building or location QR."
                ) {
                    showStub = .qrCode
                }
                Divider().padding(.leading, 56)

                ActionRow(
                    icon: "magnifyingglass",
                    iconBg: Color(red: 0.95, green: 0.55, blue: 0.20),
                    title: "Find Location",
                    subtitle: "Use the camera to identify where you are."
                ) {
                    showStub = .findLocation
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.slate100))
        }
    }
}

private struct ActionRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    let subtitle: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBg)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.slate800)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.slate500)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.slate400)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum StubAction: Identifiable {
    case qrCode
    case findLocation

    var id: String {
        switch self {
        case .qrCode: return "qr"
        case .findLocation: return "find"
        }
    }

    var title: String {
        switch self {
        case .qrCode: return "Coming soon"
        case .findLocation: return "Coming soon"
        }
    }

    var message: String {
        switch self {
        case .qrCode:
            return "QR scanning will be wired up to the location resolver in a future update."
        case .findLocation:
            return "Camera-based location lookup will be wired up to the ml-vision service in a future update."
        }
    }
}

#Preview("CameraEntry") { CameraEntryView() }
