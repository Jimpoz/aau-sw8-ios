//
//  CameraViewModel.swift
//  aau-sw8-ios
//
//  Created by jimpo on 19/02/26.
//


import AVFoundation
import Combine
import UIKit
import CoreML

final class CameraViewModel: NSObject, ObservableObject {
    enum AuthState {
        case unknown
        case authorized
        case denied
        case restricted
        case notDetermined
    }

    @Published var authState: AuthState = .unknown

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var configured = false

    override init() {
        super.init()
        observeAppLifecycle()
    }

    func configureAndMaybeStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        updateAuthState(status)

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

    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self = self else { return }
            let newStatus = AVCaptureDevice.authorizationStatus(for: .video)
            DispatchQueue.main.async {
                self.updateAuthState(newStatus)
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
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
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

            var defaultVideoDevice: AVCaptureDevice?
            if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCamera
            } else if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCamera
            } else {
                defaultVideoDevice = AVCaptureDevice.default(for: .video)
            }

            guard let device = defaultVideoDevice else {
                print("⚠️ No video device found. Are you on the iOS Simulator?")
                self.configured = false
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            } catch {
                print("⚠️ Could not create video device input: \(error)")
                self.configured = false
                return
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            }
        }
    }

    private func updateAuthState(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: authState = .authorized
        case .denied: authState = .denied
        case .restricted: authState = .restricted
        case .notDetermined: authState = .notDetermined
        @unknown default: authState = .unknown
        }
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if self?.authState == .authorized {
                self?.start()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Frame Processing, Image Recognition, 3D Image Rendering
        // TODO
    }
}
