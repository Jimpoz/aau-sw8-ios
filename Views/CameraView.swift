//
//  CameraView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var vm = CameraViewModel()
    @EnvironmentObject private var container: DIContainer
    @EnvironmentObject private var mapNav: MapNavigationCoordinator
    @EnvironmentObject private var authService: AuthService

    @State private var showDirections: Bool = false
    @State private var destinationQuery: String = ""
    @State private var directionText: String? = nil
    @State private var directionDistance: String? = nil
    @State private var isAskingDirections: Bool = false
    @State private var landmarkCapture: LandmarkCapture?
    @State private var isCapturingForLandmark: Bool = false
    @State private var findLocationMode: Bool = true

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var canRegisterLandmark: Bool {
        guard let role = authService.principal?.role?.lowercased() else { return false }
        return role == "owner" || role == "editor"
    }

    private func captureForLandmark() {
        guard !isCapturingForLandmark else { return }
        isCapturingForLandmark = true
        vm.captureNextFrame { image in
            isCapturingForLandmark = false
            landmarkCapture = image.map { LandmarkCapture(image: $0) }
        }
    }

    var body: some View {
            ZStack {
                if isPreview {
                    LinearGradient(colors: [Color(white: 0.1), .black], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                } else {
                    CameraPreview(session: vm.session)
                        .ignoresSafeArea()
                }

                GeometryReader { geo in
                    ForEach(0..<vm.boxes.count, id: \.self) { index in
                        let box = vm.boxes[index]
                        let shouldShow = box.isLandmarkMatch
                            ? (findLocationMode && box.confidence > 0.85)
                            : !findLocationMode
                        if shouldShow {
                            let x = box.rect.minX * geo.size.width
                            let width = box.rect.width * geo.size.width
                            let height = box.rect.height * geo.size.height
                            let y = (1.0 - box.rect.minY - box.rect.height) * geo.size.height

                            let stroke: Color = box.isLandmarkMatch ? .yellow : .green
                            let labelText: String = {
                                if box.isLandmarkMatch, let name = box.landmarkName {
                                    return "\(name) (\(Int(box.confidence * 100))%)"
                                }
                                return "\(box.label) (\(Int(box.confidence * 100))%)"
                            }()

                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .stroke(stroke, lineWidth: box.isLandmarkMatch ? 4 : 3)
                                    .frame(width: width, height: height)
                                    .shadow(
                                        color: box.isLandmarkMatch
                                            ? Color.yellow.opacity(0.6)
                                            : .clear,
                                        radius: box.isLandmarkMatch ? 8 : 0
                                    )

                                Text(labelText)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(stroke)
                                    .foregroundColor(.black)
                                    .offset(y: -2)
                            }
                            .position(x: x + (width / 2), y: y + (height / 2))
                        }
                    }
                }
                .ignoresSafeArea()

                VStack {
                    if showDirections, let text = directionText {
                        DirectionCard(distance: directionDistance, text: text) {
                            showDirections = false
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            isAskingDirections = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.north.line.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(showDirections ? "Change Directions" : "Ask for Directions")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.6), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.12)))
                        }

                        if canRegisterLandmark {
                            Button {
                                captureForLandmark()
                            } label: {
                                HStack(spacing: 6) {
                                    if isCapturingForLandmark {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .tint(.white)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "plus.viewfinder")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    Text("Register Landmark")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.6), in: Capsule())
                                .overlay(Capsule().stroke(Color.yellow.opacity(0.5)))
                            }
                            .disabled(isCapturingForLandmark)
                        }

                        Button {
                            findLocationMode.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: findLocationMode
                                      ? "location.viewfinder"
                                      : "viewfinder")
                                    .font(.system(size: 12, weight: .bold))
                                Text(findLocationMode ? "Find Location · ON" : "Find Location")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(findLocationMode ? .black : .white)
                            .background(
                                findLocationMode
                                    ? AnyShapeStyle(Color.yellow)
                                    : AnyShapeStyle(Color.black.opacity(0.6)),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    findLocationMode
                                        ? Color.yellow.opacity(0.6)
                                        : Color.white.opacity(0.12)
                                )
                            )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }

                if vm.authState == .denied || vm.authState == .restricted {
                    PermissionOverlay(
                        title: "Camera access is required",
                        message: "Enable camera permission in Settings",
                        primaryTitle: "Open Settings",
                        primaryAction: vm.openSettings
                    )
                }
            }
            .alert("Where to?", isPresented: $isAskingDirections) {
                TextField("e.g. A101 or Cafeteria", text: $destinationQuery)
                Button("Get Directions") { requestDirections() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Type a destination. The assistant will guide you from your current location.")
            }
            .sheet(item: $landmarkCapture) { capture in
                LandmarkRegistrationSheet(capturedImage: capture.image) { _ in
                    landmarkCapture = nil
                }
                .environmentObject(container)
            }
            .onChange(of: landmarkCapture?.id) { newId in
                // Pause the live detection stream while the registration
                // sheet is up; resume (and refresh the ORB cache) on close.
                guard !isPreview else { return }
                if newId == nil {
                    vm.resumeStreaming()
                } else {
                    vm.pauseStreaming()
                }
            }
            .onAppear {
                vm.configure(with: container, coordinator: mapNav)
                if !isPreview { vm.configureAndMaybeStart() }
            }
            .onDisappear {
                if !isPreview { vm.stop() }
            }
        }

    private func requestDirections() {
        let q = destinationQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        directionDistance = nil
        directionText = "Routing to \(q)…"
        withAnimation { showDirections = true }
    }

}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.connection?.videoOrientation = .portrait
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private struct DirectionCard: View {
    let distance: String?
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue)
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                if let distance {
                    Text(distance)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
    }
}

private struct PermissionOverlay: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .padding()
    }
}

private struct LandmarkCapture: Identifiable {
    let id = UUID()
    let image: UIImage
}

#Preview("Camera") { CameraView() }
