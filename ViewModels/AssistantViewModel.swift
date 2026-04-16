//
//  ChatItem.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation
import Combine
import SwiftUI
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

    private var llmService: LLMChatting?
    private var locationTrackingService: LocationTrackingService?
    private var cancellables = Set<AnyCancellable>()

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
    
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard connectionState.isConnected else { return }

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

