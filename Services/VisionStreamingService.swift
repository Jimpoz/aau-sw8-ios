//
//  VisionStreamingService.swift
//  aau-sw8-ios
//

import AVFoundation
import Combine
import CoreImage
import Foundation
import UIKit

final class VisionStreamingService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var detections: [DetectionBox] = []
    /// Best-guess current location name resolved by the ml-vision server.
    @Published var resolvedLocationName: String = ""

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let frameQueue = DispatchQueue(label: "ariadne.vision.frames", qos: .userInitiated)
    private let ciContext = CIContext()
    private var lastFrameSentAt: Date = .distantPast
    // Cap at 15 fps — keeps bandwidth and server load reasonable
    private let minFrameInterval: TimeInterval = 1.0 / 15.0

    /// Connect to the ml-vision streaming WebSocket.
    /// - Parameters:
    ///   - baseURL: e.g. "ws://192.168.x.x:8000"
    ///   - facilityId: facility identifier used to select the ONNX model on the server
    func connect(baseURL: String, facilityId: String) {
        guard webSocketTask == nil,
              let url = URL(string: "\(baseURL)/ws/stream/\(facilityId)") else { return }
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveNext()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.detections = []
            self.resolvedLocationName = ""
        }
    }

    func sendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isConnected, let task = webSocketTask else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFrameSentAt) >= minFrameInterval else { return }
        lastFrameSentAt = now

        frameQueue.async { [weak self] in
            guard let self, let data = self.encodeFrame(sampleBuffer) else { return }
            task.send(.data(data)) { [weak self] error in
                if let error {
                    print("[VisionStream] send error: \(error)")
                    DispatchQueue.main.async { self?.isConnected = false }
                }
            }
        }
    }

    private func encodeFrame(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        // .right rotation produces an upright portrait image for the server
        let ciImage = CIImage(cvPixelBuffer: imageBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6)
    }

    private func receiveNext() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let text: String? = {
                    switch message {
                    case .string(let s): return s
                    case .data(let d): return String(data: d, encoding: .utf8)
                    @unknown default: return nil
                    }
                }()
                if let text { self.parseFrame(text) }
                self.receiveNext()
            case .failure(let error):
                print("[VisionStream] receive error: \(error)")
                DispatchQueue.main.async { self.isConnected = false }
            }
        }
    }

    private func parseFrame(_ json: String) {
        guard let data = json.data(using: .utf8),
              let frame = try? JSONDecoder().decode(StreamFrame.self, from: data) else { return }

        let boxes = frame.detections.map {
            DetectionBox(
                rect: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height),
                label: $0.label,
                confidence: $0.confidence
            )
        }
        DispatchQueue.main.async {
            self.detections = boxes
            self.resolvedLocationName = frame.location?.name ?? ""
        }
    }
}

extension VisionStreamingService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.isConnected = true }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        DispatchQueue.main.async { self.isConnected = false }
    }
}

// MARK: - Decodable models matching serving/main.py StreamFrame

private struct StreamFrame: Decodable {
    let detections: [RemoteDetection]
    let location: RemoteLocation?
}

private struct RemoteDetection: Decodable {
    let label: String
    let confidence: Float
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

private struct RemoteLocation: Decodable {
    let kind: String
    let id: String
    let name: String
    let confidence: Double
}
