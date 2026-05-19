//
//  CameraViewModel.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/02/26.
//

import AVFoundation
import Combine
import CoreGraphics
import UIKit

struct VisionLocationToast: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published var authState: AVAuthorizationStatus = .notDetermined
    @Published var boxes: [DetectionBox] = []
    @Published var locationToast: VisionLocationToast?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var configured = false

    private let streamingService = VisionStreamingService()
    private var cancellables = Set<AnyCancellable>()

    private weak var container: DIContainer?
    private weak var mapNav: MapNavigationCoordinator?

    override init() {
        super.init()
        streamingService.$detections
            .receive(on: DispatchQueue.main)
            .assign(to: \.boxes, on: self)
            .store(in: &cancellables)
        streamingService.$resolvedLocation
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleLocationSnap(location)
            }
            .store(in: &cancellables)
    }

    func configure(with container: DIContainer, coordinator: MapNavigationCoordinator) {
        self.container = container
        self.mapNav = coordinator
    }

    private func handleLocationSnap(_ location: VisionResolvedLocation) {
        guard let container, let mapNav else { return }

        if let buildingId = location.buildingId {
            container.currentBuildingId = buildingId
        }
        if let campusId = location.campusId {
            container.currentCampusId = campusId
        }

        if let buildingId = location.buildingId {
            mapNav.pendingBuildingId = buildingId
            mapNav.pendingBuildingName = location.buildingName
            if let coord = container.floorPlanService.buildings
                .first(where: { $0.id == buildingId })?.coordinate {
                mapNav.pendingBuildingCoordinate = coord
            }
        }
        if let floorIndex = location.floorIndex {
            mapNav.pendingFloorIndex = floorIndex
        }
        
        let buildingLine = location.buildingName.map { " · \($0)" } ?? ""
        locationToast = VisionLocationToast(
            title: "Localised: \(location.name)",
            subtitle: "Floor \(location.floorIndex.map(String.init) ?? "?")\(buildingLine)"
        )
        let snapId = locationToast?.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if self?.locationToast?.id == snapId {
                    self?.locationToast = nil
                }
            }
        }
    }

    func configureAndMaybeStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authState = status

        switch status {
        case .authorized:
            setupSessionIfNeeded()
            start()
        case .notDetermined:
            requestAccess()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.authState = AVCaptureDevice.authorizationStatus(for: .video)
            }
            if granted {
                self.setupSessionIfNeeded()
                self.start()
            }
        }
    }

    func start() {
        sessionQueue.async {
            guard self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
        
        let dynamicFacility = container?.currentCampusId
            ?? AppSecrets.facilityId
        streamingService.connect(
            baseURL: AppSecrets.backendURL,
            facilityId: dynamicFacility,
            apiKey: AppSecrets.apiSecret
        )
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
        streamingService.disconnect()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func setupSessionIfNeeded() {
        guard !configured else { return }
        configured = true

        sessionQueue.async {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.session.sessionPreset = .high

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back)
                ?? AVCaptureDevice.default(for: .video)
            else {
                print("ERROR: No camera available.")
                self.configured = false
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
            } catch {
                print("Failed to create device input: \(error)")
                return
            }

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
        }
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        streamingService.sendFrame(sampleBuffer)
    }
}
