//
//  CameraView.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//  TO FIX

import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var vm = CameraViewModel()
        
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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

            // Top direction card
            VStack {
                DirectionCard()
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                Spacer()
                HStack {
                    // To add the actual level of accuracy based off the data received by the device
                    Text("Accuracy: High (GPS + WiFi)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            // Permission overlays
            if vm.authState == .denied || vm.authState == .restricted {
                PermissionOverlay(
                    title: "Camera access is required",
                    message: "Enable camera permission in Settings",
                    primaryTitle: "Open Settings",
                    primaryAction: vm.openSettings
                )
            }
        }
        .onAppear {
            if !isPreview { vm.configureAndMaybeStart() }
        }
        .onDisappear {
            if !isPreview { vm.stop() }
        }
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
    var body: some View {
        
        // Mock data for demo purposes
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
                // Get the distance information based on the user location to the next POI
                Text("20 meters")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                // Make the llm generate the text
                Text("Walk straight towards the fountain, then turn right.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
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

#Preview("Camera") { CameraView() }
