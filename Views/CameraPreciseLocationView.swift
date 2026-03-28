//
//  CameraPreciseLocationView.swift
//  aau-sw8-ios
//  
//  Uses ARKit geotracking to refine location using camera.
//

import SwiftUI
import ARKit
import RealityKit
import CoreLocation

struct CameraPreciseLocationView: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var statusText: String = "Starting camera…"
    @State private var geoTrackingSupported: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARGeoTrackingView(
                locationManager: locationManager,
                statusText: $statusText,
                geoTrackingSupported: $geoTrackingSupported
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(14)

                Text(geoTrackingSupported ? statusText : "Camera precise location is not supported.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct ARGeoTrackingView: UIViewRepresentable {
    @ObservedObject var locationManager: LocationManager
    @Binding var statusText: String
    @Binding var geoTrackingSupported: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let lidarSupported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        statusText = lidarSupported ? "LiDAR detected. Localizing…" : "Localizing (no LiDAR detected)…"

        guard ARGeoTrackingConfiguration.isSupported else {
            geoTrackingSupported = false
            statusText = "AR geotracking not supported on this device."
            return arView
        }

        geoTrackingSupported = true
        let coordinator = context.coordinator
        coordinator.setCallbacks(
            setStatus: { text in
                DispatchQueue.main.async { statusText = text }
            },
            setLocation: { loc in
                DispatchQueue.main.async {
                    locationManager.applyPreciseLocationFromCamera(loc)
                }
            }
        )

        let config = ARGeoTrackingConfiguration()

        arView.session.delegate = coordinator
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(locationManager: locationManager)
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        private let locationManager: LocationManager
        private var setStatus: ((String) -> Void)?
        private var setLocation: ((CLLocation) -> Void)?

        init(locationManager: LocationManager) {
            self.locationManager = locationManager
        }

        func setCallbacks(setStatus: @escaping (String) -> Void, setLocation: @escaping (CLLocation) -> Void) {
            self.setStatus = setStatus
            self.setLocation = setLocation
        }

        func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {
            switch geoTrackingStatus.state {
            case .notAvailable:
                setStatus?("Geotracking not available here. Move to a more open area.")
            case .initializing:
                setStatus?("Initializing geotracking…")
            case .localizing:
                setStatus?("Localizing with camera…")
            case .localized:
                setStatus?("Localized. Getting precise coordinates…")
                requestCameraGeolocation(from: session)
            @unknown default:
                setStatus?("Localizing…")
            }
        }

        private func requestCameraGeolocation(from session: ARSession) {
            guard let frame = session.currentFrame else { return }

            
            let t = frame.camera.transform
            let cameraWorldPoint = simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)

            session.getGeoLocation(forPoint: cameraWorldPoint) { coordinate, altitude, error in
                if let error {
                    self.setStatus?("Failed to get geo coordinates: \(error.localizedDescription)")
                    return
                }

                // coordinate is already valid here (non-optional)
                let loc = CLLocation(
                    coordinate: coordinate,
                    altitude: altitude,
                    horizontalAccuracy: 10,
                    verticalAccuracy: 10,
                    timestamp: Date()
                )

                self.setLocation?(loc)
                self.setStatus?("Precise location updated.")
            }
        }
    }
}

