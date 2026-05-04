//
//  AssistantService.swift
//  aau-sw8-ios
//
//  Created by jimpo on 17/02/26.
//

import Foundation
import Combine

/// Service for communicating with the backend LLM + RAG assistant
final class AssistantService: NSObject, ObservableObject, LLMChatting {
    private let backendURL: String
    private let campusId: String
    private let session: URLSession
    
    struct ChatRequest: Codable {
        let user_query: String
        let campus_id: String
        let building_id: String?
        let user_lat: Double?
        let user_lon: Double?
        let current_location_space_id: String?
        let current_location_coords: CoordinateData?

        struct CoordinateData: Codable {
            let x: Double
            let y: Double
        }
    }
    
    struct ChatResponse: Codable {
        let answer: String
        let sources: [String]
    }
    
    init(
        backendURL: String = AppSecrets.backendURL,
        campusId: String = "campus_001",
        session: URLSession = {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            return URLSession(configuration: config)
        }()
    ) {
        self.backendURL = backendURL
        self.campusId = campusId
        self.session = session
        super.init()
    }
    
    func send(userText: String, context: [String : Any]) async throws -> String {
        // Extract location from context if available
        let spaceId = context["space_id"] as? String
        let buildingId = context["building_id"] as? String
        let x = context["x"] as? Double
        let y = context["y"] as? Double

        let coords: ChatRequest.CoordinateData?
        if let x = x, let y = y {
            coords = ChatRequest.CoordinateData(x: x, y: y)
        } else {
            coords = nil
        }

        let request = ChatRequest(
            user_query: userText,
            campus_id: campusId,
            building_id: buildingId,
            user_lat: y,
            user_lon: x,
            current_location_space_id: spaceId,
            current_location_coords: coords
        )
        
        // Encode request
        let encoder = JSONEncoder()
        let requestBody = try encoder.encode(request)
        
        // Prepare URL and URLRequest
        guard let url = URL(string: "\(backendURL)/api/v1/assistant/chat") else {
            throw URLError(.badURL)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        urlRequest.attachBearer()
        urlRequest.httpBody = requestBody
        urlRequest.timeoutInterval = 30
        
        // Execute request
        let (data, response) = try await session.data(for: urlRequest)
        
        // Verify HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw URLError(.init(rawValue: httpResponse.statusCode), userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorMessage)"
            ])
        }
        
        // Decode response
        let decoder = JSONDecoder()
        let chatResponse = try decoder.decode(ChatResponse.self, from: data)
        
        return chatResponse.answer
    }
    
    /// Ping the backend health endpoint
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(backendURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        request.attachBearer()
        request.timeoutInterval = 8
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    /// Retrieve available space types for suggestions
    /// - Returns: List of space types the assistant can help find
    /// - Throws: NetworkError or DecodingError
    func getAvailableSpaceTypes() async throws -> [String] {
        guard let url = URL(string: "\(backendURL)/api/v1/assistant/spaces-by-type?campus_id=\(campusId)&space_type=*") else {
            throw URLError(.badURL)
        }

        var spaceTypesRequest = URLRequest(url: url)
        spaceTypesRequest.setValue(AppSecrets.apiSecret, forHTTPHeaderField: "X-Api-Key")
        spaceTypesRequest.attachBearer()
        let (data, response) = try await session.data(for: spaceTypesRequest)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        struct SpaceTypesResponse: Codable {
            let available_types: [String]
        }
        
        let decoder = JSONDecoder()
        let typesResponse = try decoder.decode(SpaceTypesResponse.self, from: data)
        return typesResponse.available_types
    }
}
