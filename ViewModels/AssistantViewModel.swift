//
//  ChatItem.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation
import Combine

struct ChatItem: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
}

final class AssistantViewModel: ObservableObject {
    @Published var messages: [ChatItem] = [] // UI-only
    @Published var input: String = ""

    init() {
        addWelcomeMessage()
    }
    
    private func addWelcomeMessage() {
        let welcome = ChatItem(
            role: .assistant,
            text: "Hello 👋 I'm your virtual assistant. How can I help you today?"
        )
        messages.append(welcome)
    }
    
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(.init(role: .user, text: text))
        input = ""
        // UI-only placeholder
        messages.append(.init(role: .assistant, text: "Sorry, unfortunately I'm currently unavailable. Try again later!"))
    }
}
