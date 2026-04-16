//
//  ChatItem.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation
import Combine
import SwiftUI
import Speech
import AVFoundation
internal import _LocationEssentials

struct ChatItem: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

enum ConnectionState: Equatable {
    case checking
    case connected
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var dotColor: Color {
        switch self {
        case .checking: return Color.orange
        case .connected: return Color.success
        case .failed:   return Color.red
        }
    }

    var statusText: String {
        switch self {
        case .checking:        return "Connecting…"
        case .connected:       return "Online • AI Powered Guide"
        case .failed(let msg): return "Failed to connect: \(msg)"
        }
    }
}

final class AssistantViewModel: ObservableObject {
    @Published var messages: [ChatItem] = []
    @Published var input: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var connectionState: ConnectionState = .checking
    @Published var isRecording: Bool = false
    @Published var speechPermissionDenied: Bool = false

    private var llmService: LLMChatting?
    private var locationTrackingService: LocationTrackingService?
    private var cancellables = Set<AnyCancellable>()

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()
    private var tapInstalled = false

    init(llmService: LLMChatting? = nil, locationTrackingService: LocationTrackingService? = nil) {
        self.llmService = llmService
        self.locationTrackingService = locationTrackingService
        addWelcomeMessage()
    }

    func configure(with container: DIContainer) {
        self.llmService = container.llm
        self.locationTrackingService = container.locationTrackingService
        checkConnection()
    }

    func checkConnection() {
        guard let service = llmService else {
            connectionState = .failed("Service not configured")
            return
        }
        connectionState = .checking
        Task {
            let reachable = await service.checkHealth()
            await MainActor.run {
                self.connectionState = reachable ? .connected : .failed("Can't reach assistant")
                if !reachable {
                    self.messages.append(.init(
                        role: .assistant,
                        text: "Unable to reach the assistant service. Check your network and tap Retry."
                    ))
                }
            }
        }
    }
    
    private func addWelcomeMessage() {
        let welcome = ChatItem(
            role: .assistant,
            text: "Hello! I'm your virtual assistant. How can I help you today?"
        )
        messages.append(welcome)
    }
    
    func toggleVoiceInput() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            await MainActor.run { speechPermissionDenied = true }
            return
        }

        let micGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            await MainActor.run { speechPermissionDenied = true }
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            await MainActor.run {
                messages.append(.init(role: .assistant,
                    text: "Speech recognition is not available on this device or in this language."))
            }
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.input = text }
            }
            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            await MainActor.run { self.isRecording = true }
        } catch {
            stopRecording()
        }
    }

    func stopRecording() {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async { self.isRecording = false }
    }


    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard connectionState.isConnected else { return }

        if isRecording { stopRecording() }

        messages.append(.init(role: .user, text: text))
        input = ""

        guard let llmService = llmService else {
            messages.append(.init(role: .assistant, text: "Assistant service not available. Please check your connection."))
            return
        }
        
        isLoading = true
        error = nil
        
        var context: [String: Any] = [:]
        if let location = locationTrackingService?.currentLocation {
            context["x"] = location.longitude
            context["y"] = location.latitude
        }
        
        Task {
            do {
                let response = try await llmService.send(userText: text, context: context)
                
                DispatchQueue.main.async {
                    self.messages.append(.init(role: .assistant, text: response))
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.messages.append(.init(
                        role: .assistant,
                        text: "Error: \(error.localizedDescription)\n\nPlease ensure the backend service is running."
                    ))
                    self.isLoading = false
                }
            }
        }
    }
}

