//
//  CameraViewModel.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/02/26.
//

import AVFoundation
import Combine
import CoreGraphics
import CoreImage
import CoreLocation
import UIKit

@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    @Published var authState: AVAuthorizationStatus = .notDetermined
    @Published var boxes: [DetectionBox] = []

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var configured = false

    private let streamingService = VisionStreamingService()
    private var cancellables = Set<AnyCancellable>()

    private weak var container: DIContainer?
    private weak var mapNav: MapNavigationCoordinator?

    private var pendingFrameCapture: ((UIImage?) -> Void)?
    private let captureLock = NSLock()
    private let frameConvertContext = CIContext()

    private var lastHandledSpaceId: String?

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

    /// Capture the next live frame as a UIImage. Used by the landmark
    /// registration sheet to freeze "what the user is pointing at" the
    /// moment they tap Register. The completion fires on the main
    /// thread; only one capture can be pending at a time.
    func captureNextFrame(_ completion: @escaping (UIImage?) -> Void) {
        captureLock.lock()
        pendingFrameCapture = completion
        captureLock.unlock()
    }

    private func handleLocationSnap(_ location: VisionResolvedLocation) {
        guard let container, let mapNav else { return }


        let snapKey = location.spaceId ?? location.id
        if snapKey == lastHandledSpaceId { return }
        lastHandledSpaceId = snapKey

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
        mapNav.pendingFloorIndex = location.floorIndex
        mapNav.pendingFloorId = location.floorId

        if let spaceId = location.spaceId {
            container.forcedUserSpaceId = spaceId
        }
        if let lat = location.centroidLat, let lng = location.centroidLng {
            container.forcedUserCoordinate = CLLocationCoordinate2D(
                latitude: lat, longitude: lng,
            )
        } else {
            container.forcedUserCoordinate = nil
        }

        mapNav.selectedTab = .floorPlan
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
        lastHandledSpaceId = nil
    }

    func pauseStreaming() {
        streamingService.disconnect()
        boxes = []
    }

    func resumeStreaming() {
        lastHandledSpaceId = nil
        let dynamicFacility = container?.currentCampusId
            ?? AppSecrets.facilityId
        streamingService.connect(
            baseURL: AppSecrets.backendURL,
            facilityId: dynamicFacility,
            apiKey: AppSecrets.apiSecret
        )
    }

    func reconnectWithCampus(_ campusId: String) {
        streamingService.disconnect()
        boxes = []
        lastHandledSpaceId = nil
        guard container != nil else { return }
        streamingService.connect(
            baseURL: AppSecrets.backendURL,
            facilityId: campusId,
            apiKey: AppSecrets.apiSecret
        )
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

        // Drain a one-shot capture request if the sheet asked for one.
        // We grab the buffer's pixel data and convert it on the same
        // queue (sessionQueue) the AVCapture delegate runs on, then
        // hop to the main actor to deliver the UIImage.
        captureLock.lock()
        let pending = pendingFrameCapture
        if pending != nil { pendingFrameCapture = nil }
        captureLock.unlock()

        guard let pending,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(.right)
        let cgImage = frameConvertContext.createCGImage(ciImage, from: ciImage.extent)
        let uiImage = cgImage.map { UIImage(cgImage: $0) }
        DispatchQueue.main.async { pending(uiImage) }
    }
}
