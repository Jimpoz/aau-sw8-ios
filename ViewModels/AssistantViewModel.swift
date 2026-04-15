//
//  ChatItem.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation
import Combine
internal import _LocationEssentials

struct ChatItem: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

final class AssistantViewModel: ObservableObject {
    @Published var messages: [ChatItem] = []
    @Published var input: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    private var llmService: LLMChatting?
    private var locationTrackingService: LocationTrackingService?
    private var cancellables = Set<AnyCancellable>()

    init(llmService: LLMChatting? = nil, locationTrackingService: LocationTrackingService? = nil) {
        self.llmService = llmService
        self.locationTrackingService = locationTrackingService
        addWelcomeMessage()
    }
    
    /// Configure view model with DI container services
    func configure(with container: DIContainer) {
        self.llmService = container.llm
        self.locationTrackingService = container.locationTrackingService
    }
    
    private func addWelcomeMessage() {
        let welcome = ChatItem(
            role: .assistant,
            text: "Hello 👋 I'm your virtual assistant. How can I help you today? Ask me about locations, directions, facilities, or services in the building."
        )
        messages.append(welcome)
    }
    
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Add user message
        messages.append(.init(role: .user, text: text))
        input = ""
        
        // Guard that we have an LLM service
        guard let llmService = llmService else {
            messages.append(.init(role: .assistant, text: "⚠️ Assistant service not available. Please check your connection."))
            return
        }
        
        isLoading = true
        error = nil
        
        // Prepare context from current location
        var context: [String: Any] = [:]
        if let location = locationTrackingService?.currentLocation {
            context["x"] = location.longitude
            context["y"] = location.latitude
            // Note: space_id would come from floor plan tracking, not CLLocationCoordinate2D
        }
        
        // Call LLM service asynchronously
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
                        text: "❌ Error: \(error.localizedDescription)\n\nPlease ensure the backend service is running."
                    ))
                    self.isLoading = false
                }
            }
        }
    }
}

