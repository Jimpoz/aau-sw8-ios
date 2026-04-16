//
//  SpatialQuerying.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//


import Foundation

// Minimale contracts for a working demo without backend

public protocol SpatialQuerying {
    var availableFloors: [Int] { get }
    func currentFloor() -> Int?
}

public protocol LLMChatting {
    func send(userText: String, context: [String: Any]) async throws -> String
    func checkHealth() async -> Bool
}

public extension LLMChatting {
    func checkHealth() async -> Bool { return true }
}
