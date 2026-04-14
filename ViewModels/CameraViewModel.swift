//
//  CameraViewModel.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/02/26.
//


import AVFoundation
import Vision
import CoreGraphics
import UIKit
import Combine

final class CameraViewModel: NSObject, ObservableObject {
    // Could decrease the number of states
    
    @Published var authState: AVAuthorizationStatus = .notDetermined
    @Published var boxes: [DetectionBox] = []

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private let videoOutput = AVCaptureVideoDataOutput()
    private var visionRequests: [VNRequest] = []
    private var configured = false

    override init() {
        super.init()
        setupVision()
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
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
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

            // Video output
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self,
                                                     queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
        }
    }

    private func setupVision() {
        do {
            // Based on YOLOv3 model -> to change
            let config = MLModelConfiguration()
            let model = try YOLOv3(configuration: config).model
            let visionModel = try VNCoreMLModel(for: model)

            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                self?.handleDetectionResults(request: request, error: error)
            }

            request.imageCropAndScaleOption = .scaleFill
            visionRequests = [request]

        } catch {
            print("Failed to create VNCoreMLModel: \(error)")
        }
    }

    private func handleDetectionResults(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

        let newBoxes = results.map { obs in
            DetectionBox(
                rect: obs.boundingBox,
                label: obs.labels.first?.identifier ?? "Object",
                confidence: obs.labels.first?.confidence ?? 0
            )
        }

        DispatchQueue.main.async {
            self.boxes = newBoxes
        }
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .right,
            options: [:]
        )

        try? handler.perform(self.visionRequests)
    }
}
